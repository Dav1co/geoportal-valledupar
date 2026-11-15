begin;
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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '783d675b8c5e2f0ce8a5e339e8fd1d61' then
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 20 — VISTAS: v_dano (tiempos, estado y pérdida calculados), v_reporte_externo y la epicrisis con daños
-- PROPUESTA. No se ha ejecutado en la base real. Nada se escribe calculado: todo se deriva en las vistas.
-- =====================================================================

-- Tiempos vigentes de la reparación: el último valor no nulo de cada uno.
create view redes.v_dano_tiempos as
select d.id as dano_id,
       (select t.t_inicio_reparacion from redes.dano_tiempos t where t.dano_id = d.id and t.t_inicio_reparacion is not null order by t.id desc limit 1) as t_inicio_reparacion,
       (select t.t_restablecido from redes.dano_tiempos t where t.dano_id = d.id and t.t_restablecido is not null order by t.id desc limit 1) as t_restablecido
  from redes.danos d;

-- Daño con sus cálculos (01 §B):
--   respuesta = inicio de la reparación − detectado; reparación = restablecido − inicio de la reparación;
--   total = restablecido (o ahora, si sigue abierto) − (inicio del daño, o detectado);
--   estado: oculto (último ocultar/reincluir) > atendido (evento «atendido» después del último «reabrir», o restablecido) > en atención (hay inicio de reparación) > reportado;
--   pérdida = caudal de fuga (caudales_fuga por diámetro del activo, tipo de rotura y presión) × total. Sin tabla, «sin_tabla» y nula.
create view redes.v_dano as
with b as (
  select d.*, tm.t_inicio_reparacion, tm.t_restablecido,
         (select e.tipo = 'ocultar' from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('ocultar', 'reincluir') order by e.id desc limit 1) as ev_oculto,
         (select e.tipo from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('atendido', 'reabrir', 'en_atencion') order by e.id desc limit 1) as ev_estado,
         (select a.codigo from redes.activos a where a.id = d.activo_id) as activo_codigo,
         (select v.diametro_mm from redes.activo_vigente_mat v where v.activo_id = d.activo_id) as diametro_mm
    from redes.danos d join redes.v_dano_tiempos tm on tm.dano_id = d.id),
c as (
  select b.*,
         case when coalesce(b.ev_oculto, false) then 'oculto'
              when b.ev_estado = 'atendido' or (b.t_restablecido is not null and b.ev_estado is distinct from 'reabrir') then 'atendido'
              when b.t_inicio_reparacion is not null or b.ev_estado in ('en_atencion', 'reabrir') then 'en_atencion'
              else 'reportado' end as estado,
         extract(epoch from (b.t_inicio_reparacion - b.t_detectado))::bigint as respuesta_s,
         extract(epoch from (b.t_restablecido - b.t_inicio_reparacion))::bigint as reparacion_s,
         extract(epoch from (coalesce(b.t_restablecido, clock_timestamp()) - coalesce(b.t_inicio_dano, b.t_detectado)))::bigint as total_s,
         b.t_restablecido is null as total_corre,
         (select q.caudal_lps from redes.caudales_fuga q
           where q.tipo_rotura = b.tipo_rotura and b.diametro_mm between q.diametro_min_mm and q.diametro_max_mm
             and (b.presion_mca is null and q.presion_min_mca is null and q.presion_max_mca is null
                  or b.presion_mca between coalesce(q.presion_min_mca, 0) and coalesce(q.presion_max_mca, 1000))
           order by q.vigente_desde desc, q.id desc limit 1) as caudal_lps
    from b)
select c.id, c.codigo, c.clase, c.tipo_codigo, (select t.nombre from redes.tipos_dano t where t.codigo = c.tipo_codigo) as tipo_nombre,
       c.sistema, c.activo_id, c.activo_codigo, c.no_ident_que_es, c.lat, c.lon, c.geom, c.ubicacion_origen, c.precision_m, c.fuera_de_zona,
       c.t_inicio_dano, c.t_detectado, c.t_inicio_reparacion, c.t_restablecido, c.inicio_en, c.inicio_origen,
       c.tipo_rotura, c.largo_afectado_m, c.presion_mca, c.usuarios_sin_servicio, c.usuarios_propuesta, c.sector_texto, c.riesgo, c.marcas,
       c.causa_clase, c.causa_codigo, c.tercero_tipo, c.descripcion, c.origen, c.reporte_externo_id, c.autor, c.registrado_en,
       c.estado, c.respuesta_s, c.reparacion_s, c.total_s, c.total_corre, c.caudal_lps,
       case when c.caudal_lps is not null then round(c.caudal_lps * c.total_s / 1000.0, 1) end as perdida_m3,
       case when c.caudal_lps is not null then 'calculada'
            when c.clase = 'falla' or c.tipo_rotura is null then 'no_aplica'
            when not exists (select 1 from redes.caudales_fuga) then 'sin_tabla'
            when c.diametro_mm is null then 'sin_diametro'
            else 'sin_fila' end as perdida_estado
  from c;

-- Reporte del bot con su estado vigente y el que se le devuelve al bot (recibido, en atención, atendido o descartado).
create view redes.v_reporte_externo as
select r.id, r.radicado, r.canal, r.origen, r.tipo_bot, r.lat, r.lon, r.geom, r.direccion, r.descripcion, r.recibido_en, r.registrado_en,
       e.tipo as ultimo_evento, e.dano_id, d.codigo as dano_codigo, d.estado as dano_estado,
       case e.tipo when 'descartado' then 'descartado'
                   when 'convertido' then case d.estado when 'atendido' then 'atendido' else 'en_atencion' end
                   when 'atendido' then 'atendido' when 'en_atencion' then 'en_atencion' else 'recibido' end as estado_bot,
       (select count(*) from redes.reporte_externo_fotos f where f.reporte_id = r.id) as fotos
  from redes.reportes_externos r
  left join lateral (select x.tipo, x.dano_id from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) e on true
  left join redes.v_dano d on d.id = e.dano_id;

-- Epicrisis: la del 1a (altas, versiones, eventos y componentes) MÁS los daños y fallas del activo (clase «dano» o «falla»).
-- Mismas columnas que en el 1a. La reversa deja el texto del 1a.
create or replace view redes.v_epicrisis as
select v.activo_id, v.creado_en as cuando, case when v.version = 1 then 'alta' else 'version' end as clase, v.id as ref_id,
       case when v.version = 1 then 'Alta del activo' else 'Versión ' || v.version end
         || case when v.carga_id is not null then ' (carga ' || v.carga_id || ')' else ' (ficha)' end as resumen,
       case when v.carga_id is not null and exists (select 1 from redes.carga_eventos e where e.carga_id = v.carga_id and e.tipo = 'revertir') then 'revertida' else 'vigente' end as estado,
       v.autor
  from redes.activo_versiones v
union all
select e.activo_id, e.creado_en, 'evento_' || e.tipo, e.id, e.motivo, null, e.autor from redes.activo_eventos e
union all
select c.padre_id, c.creado_en, 'componente_' || c.accion, c.id, 'Componente ' || h.codigo || ': ' || c.motivo, null, c.autor
  from redes.activo_componentes c join redes.activos h on h.id = c.hijo_id
union all
select c.hijo_id, c.creado_en, 'es_componente_' || c.accion, c.id, 'Parte de ' || p.codigo || ': ' || c.motivo, null, c.autor
  from redes.activo_componentes c join redes.activos p on p.id = c.padre_id
union all
-- Daños y fallas: el ref_id es el número del código (DAN-000123 → 123), para paginar con el mismo cursor.
select d.activo_id, d.t_detectado, d.clase, substring(d.codigo from 5)::bigint,
       d.codigo || ' · ' || d.tipo_nombre
         || coalesce(' · ' || (select r.nombre from redes.tipos_rotura r where r.codigo = d.tipo_rotura), '')
         || ' · riesgo ' || d.riesgo
         || case d.causa_clase when 'propia' then ' · causa propia' when 'terceros' then ' · causa de terceros' else ' · causa desconocida' end
         || case when d.total_corre then '' else ' · duración ' || (d.total_s / 3600) || ' h ' || lpad(((d.total_s % 3600) / 60)::text, 2, '0') || ' min' end
         || case when d.perdida_m3 is not null then ' · pérdida ≈ ' || d.perdida_m3 || ' m³' else '' end,
       case d.estado when 'reportado' then 'Reportado' when 'en_atencion' then 'En atención' when 'atendido' then 'Atendido' else 'Oculto' end,
       d.autor
  from redes.v_dano d
 where d.activo_id is not null and d.estado <> 'oculto';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 25 — RPC: formulario, preparar y crear el daño; minimapa (buscar, nodos de un tramo y tesela);
-- reportes del bot (recibir, convertir en daño y descartar)
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Captura: tecnica.f_autorizar_captura(correo, 'danos_fallas') — la clave ya existe: el operador necesita el formulario asignado en Personal;
-- supervisor y administrador pasan siempre. Minimapa: el perfil de lectura del 1b (operador, supervisor o administrador de Técnica).
-- =====================================================================

-- Texto ISO con zona → timestamptz, o error para la persona.
create function redes.f_instante(p_valor text, p_rotulo text) returns timestamptz
language plpgsql stable set search_path to 'pg_catalog' as $f$
begin
  if p_valor is null or btrim(p_valor) = '' then return null; end if;
  if length(p_valor) > 40 or p_valor !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    perform tecnica.f_error(format('La hora «%s» no viene en la forma esperada', p_rotulo));
  end if;
  return p_valor::timestamptz;
exception when others then
  if sqlstate = '22023' then raise; end if;
  perform tecnica.f_error(format('La hora «%s» no es válida', p_rotulo));
  return null;
end $f$;

-- ---------- Formulario: catálogos y reglas para la pantalla ----------
create function public.geoportal_redes_formulario_dano(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas');
begin
  return jsonb_build_object(
    'perfil', tecnica.f_perfil(v_email),
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'clase', clase, 'nombre', nombre, 'sistemas', to_jsonb(sistemas), 'pide_rotura', pide_rotura) order by orden) from redes.tipos_dano where activo),
    'roturas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.tipos_rotura where activo),
    'causas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.causas where activo),
    'terceros', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.tipos_tercero where activo),
    'marcas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.marcas_riesgo where activo),
    'reglas', jsonb_build_object('dias_atras_max', redes.f_param('dano_dias_atras_max'), 'min_fotos', redes.f_param('min_fotos_dano'), 'max_fotos', redes.f_param('max_fotos_dano'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_dano'), 'max_horas_inicio', tecnica.f_max_horas_inicio(),
                                 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'hay_tabla_caudales', exists (select 1 from redes.caudales_fuga),
    'ahora', clock_timestamp());
end $f$;

-- ---------- Preparar: reserva el id del daño y las rutas de las fotos (la Edge firma las URL de subida) ----------
create function public.geoportal_redes_preparar_dano(p_solicitante text, p_fotos integer)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_max integer := redes.f_param('max_fotos_dano')::integer;
begin
  if p_fotos is null or p_fotos < redes.f_param('min_fotos_dano') or p_fotos > v_max then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, v_max));
  end if;
  insert into redes.dano_preparaciones (dano_id, autor, fotos) values (v_id, v_email, p_fotos);
  return jsonb_build_object('dano_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', (select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'danos/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n));
end $f$;

-- ---------- Crear el daño (una sola transacción). Hora oficial = servidor; autor = solicitante verificado; el reenvío con el mismo id no duplica. ----------
-- p_datos: {clase, tipo, sistema, activo | no_identificado, lat, lon, precision_m, ubicacion_origen, t_inicio_dano, t_detectado,
--           t_inicio_reparacion, t_restablecido, inicio_dispositivo, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector,
--           riesgo, marcas[], causa_clase, causa, tercero_tipo, tercero_nombre, descripcion, fotos[{n, momento, ruta}]}
create function public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
  end if;
  if not exists (select 1 from redes.dano_preparaciones where dano_id = p_id and autor = v_email) then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos del daño no son válidos'); end if;

  -- qué pasó
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija qué pasó'); end if;
  if d ->> 'clase' is distinct from v_tipo.clase then perform tecnica.f_error('El tipo elegido no corresponde a daño o falla'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error(format('«%s» no aplica a %s', v_tipo.nombre, d ->> 'sistema')); end if;

  -- activo o «no identificado»
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación del daño'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');

  -- tiempos (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio_dano', 'inicio del daño');
  v_t_det := redes.f_instante(d ->> 't_detectado', 'detectado');
  v_t_rep := redes.f_instante(d ->> 't_inicio_reparacion', 'inicio de la reparación');
  v_t_res := redes.f_instante(d ->> 't_restablecido', 'servicio restablecido');
  if v_t_det is null then perform tecnica.f_error('Escriba cuándo se detectó'); end if;
  if greatest(v_t_ini, v_t_det, v_t_rep, v_t_res) > v_ahora + interval '2 minutes' then perform tecnica.f_error('Hay una hora en el futuro: revise la hora de su celular'); end if;
  if v_t_det < v_ahora - make_interval(days => redes.f_param('dano_dias_atras_max')::integer) then
    perform tecnica.f_error(format('La detección no puede ser de hace más de %s días', redes.f_param('dano_dias_atras_max')::integer));
  end if;
  if v_t_ini is not null and v_t_ini > v_t_det then perform tecnica.f_error('El inicio del daño no puede ser después de la detección'); end if;
  if v_t_rep is not null and v_t_rep < v_t_det then perform tecnica.f_error('El inicio de la reparación no puede ser antes de la detección'); end if;
  if v_t_res is not null and v_t_rep is null then perform tecnica.f_error('Para el servicio restablecido, escriba también el inicio de la reparación'); end if;
  if v_t_res is not null and v_t_res < v_t_rep then perform tecnica.f_error('El servicio restablecido no puede ser antes del inicio de la reparación'); end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- tamaño, afectación, riesgo y causa
  if d ->> 'tipo_rotura' is not null and not exists (select 1 from redes.tipos_rotura where codigo = d ->> 'tipo_rotura' and activo) then perform tecnica.f_error('El tipo de rotura no existe'); end if;
  if d ->> 'tipo_rotura' is not null and not v_tipo.pide_rotura then perform tecnica.f_error('Este tipo de daño no lleva tipo de rotura'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if d -> 'marcas' is not null and jsonb_typeof(d -> 'marcas') <> 'array' then perform tecnica.f_error('Las marcas de riesgo no son válidas'); end if;
  v_marcas := coalesce(array(select distinct jsonb_array_elements_text(d -> 'marcas')), '{}');
  if exists (select 1 from unnest(v_marcas) m where not exists (select 1 from redes.marcas_riesgo r where r.codigo = m and r.activo)) then perform tecnica.f_error('Una marca de riesgo no existe'); end if;
  if coalesce(d ->> 'causa_clase', '') not in ('propia', 'terceros', 'desconocida') then perform tecnica.f_error('Elija la causa: propia, de terceros o desconocida'); end if;
  if d ->> 'causa_clase' = 'propia' then
    v_causa := d ->> 'causa';
    if not exists (select 1 from redes.causas where codigo = v_causa and activo) then perform tecnica.f_error('Elija la causa propia'); end if;
  elsif d ->> 'causa_clase' = 'terceros' then
    v_ter := d ->> 'tercero_tipo';
    if not exists (select 1 from redes.tipos_tercero where codigo = v_ter and activo) then perform tecnica.f_error('Elija quién lo causó'); end if;
    v_ter_nom := nullif(btrim(coalesce(d ->> 'tercero_nombre', '')), '');
    if v_ter_nom is not null and length(v_ter_nom) not between 2 and 120 then perform tecnica.f_error('El nombre, la empresa o la placa lleva de 2 a 120 caracteres'); end if;
  end if;
  if v_desc is not null and length(v_desc) > 1000 then perform tecnica.f_error('La descripción admite hasta 1.000 caracteres'); end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
  end if;
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  if v_n > 0 and not exists (select 1 from jsonb_array_elements(v_fotos) e where e ->> 'momento' = 'dano') then perform tecnica.f_error('Falta una foto del daño'); end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'momento', '') not in ('dano', 'entorno', 'reparado') then perform tecnica.f_error('Cada foto dice si es del daño, del entorno o de la reparación'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^danos/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este daño', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'momento', v_f ->> 'momento', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código DAN-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, precision_m, fuera_de_zona,
         t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto,
         riesgo, marcas, causa_clase, causa_codigo, tercero_tipo, descripcion, origen, autor, registrado_en)
  values (p_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_activo, v_noid, round(v_lat, 6), round(v_lon, 6), d ->> 'ubicacion_origen',
          (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_det, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          d ->> 'tipo_rotura', (d ->> 'largo_afectado_m')::numeric, (d ->> 'presion_mca')::numeric, (d ->> 'usuarios_sin_servicio')::integer,
          nullif(btrim(coalesce(d ->> 'sector', '')), ''), d ->> 'riesgo', v_marcas, d ->> 'causa_clase', v_causa, v_ter, v_desc, 'formulario', v_email, v_ahora);
  if v_ter_nom is not null then insert into redes.dano_datos_sensibles (dano_id, tercero_nombre) values (p_id, v_ter_nom); end if;
  if v_t_rep is not null then insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor) values (p_id, v_t_rep, v_t_res, 'formulario', v_email); end if;
  insert into redes.dano_fotos (dano_id, n, momento, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'momento', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $f$;

-- ---------- Minimapa ----------
-- Búsqueda por código (del geoportal o de la capa) o por el nombre visible del tipo; máximo 10. Sin GPS, o si el activo no aparece.
create function public.geoportal_redes_activo_buscar(p_solicitante text, p_texto text, p_sistema text default null, p_limite integer default 10)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v text := btrim(coalesce(p_texto, '')); v_lim integer := coalesce(p_limite, 10);
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if length(v) < 2 or length(v) > 60 then perform tecnica.f_error('Escriba de 2 a 60 caracteres'); end if;
  if p_sistema is not null and p_sistema not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Ese sistema no existe'); end if;
  if v_lim < 1 or v_lim > 10 then perform tecnica.f_error('Se piden de 1 a 10 activos'); end if;
  return jsonb_build_object('activos', coalesce((
    select jsonb_agg(redes.f_activo_corto(x.activo_id) || jsonb_build_object('sistema', x.sistema, 'lat', x.lat, 'lon', x.lon) order by x.rango, x.codigo)
      from (select m.activo_id, m.codigo, m.sistema,
                   round(ST_Y(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lat,
                   round(ST_X(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lon,
                   case when m.codigo = upper(v) or lower(m.codigo_anterior) = lower(v) then 0 else 1 end as rango
              from redes.activo_vigente_mat m
             where not m.retirado and not m.oculto and (p_sistema is null or m.sistema = p_sistema)
               and (m.codigo like upper(v) || '%' or lower(m.codigo_anterior) like lower(v) || '%')
             order by rango, m.codigo limit v_lim) x), '[]'::jsonb));
end $f$;

-- Un tramo y sus nodos (los dos extremos), para elegir el tramo o uno de sus nodos en el minimapa.
create function public.geoportal_redes_tramo_nodos(p_solicitante text, p_codigo text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v_id bigint; m redes.activo_vigente_mat%rowtype;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  v_id := redes.f_buscar_activo(p_codigo);
  select * into m from redes.activo_vigente_mat where activo_id = v_id;
  if GeometryType(m.geom) not in ('LINESTRING', 'MULTILINESTRING') then perform tecnica.f_error('Ese activo no es un tramo'); end if;
  return jsonb_build_object('tramo', redes.f_activo_corto(v_id) || jsonb_build_object('sistema', m.sistema, 'longitud_m', m.longitud_m, 'diametro_mm', m.diametro_mm),
    'nodos', coalesce((select jsonb_agg(jsonb_build_object('rol', x.rol, 'nombre', n.nombre_visible, 'lat', round(ST_Y(n.geom)::numeric, 6), 'lon', round(ST_X(n.geom)::numeric, 6),
                                                         'activo', case when n.activo_id is not null and exists (select 1 from redes.activo_vigente_mat a where a.activo_id = n.activo_id and not a.retirado)
                                                                        then redes.f_activo_corto(n.activo_id) end) order by x.o)
                         from redes.v_tramo_nodos_vigente tn
                         cross join lateral (values ('inicio', 1, tn.nodo_ini), ('fin', 2, tn.nodo_fin)) x(rol, o, nodo)
                         join redes.v_nodo_visible n on n.nodo_id = x.nodo
                        where tn.activo_id = v_id), '[]'::jsonb));
end $f$;

-- Tesela liviana del minimapa (perfil «mini», 01 §I): una sola red, desde el zoom mini_zoom_min; los accesorios desde mini_zoom_acc.
-- Atributos: código, prefijo, clase, forma (tramo o nodo) y si va punteado. Nada de material, edad ni origen. Devuelve la tesela MVT en base64.
create function public.geoportal_redes_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer, p_sistema text)
returns text language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v_env geometry; v bytea;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p_sistema not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija acueducto o alcantarillado'); end if;
  if p_z is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < redes.f_param('mini_zoom_min') then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  select ST_AsMVT(t, 'red', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, coalesce(m.clase, '') as clase,
           case when GeometryType(m.geom) = 'POINT' then 'nodo' else 'tramo' end as forma, m.punteado
      from redes.activo_vigente_mat m
     where m.sistema = p_sistema and not m.retirado and not m.oculto
       and m.geom && ST_Transform(v_env, 4326)
       and (m.prefijo <> 'ACC' or p_z >= redes.f_param('mini_zoom_acc'))) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $f$;

-- ---------- Reportes del bot (N-14) ----------
-- Entrada (interna; la función pública para n8n, con su credencial propia, va DESPUÉS de la fase 1). Idempotente por (canal, radicado).
-- NO recibe nombre ni teléfono: si vienen en el JSON, se rechaza.
create function redes.f_reporte_externo_recibir(p jsonb) returns uuid
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare v_id uuid;
begin
  if p ?| array['nombre', 'telefono', 'teléfono', 'celular', 'cedula', 'cédula', 'correo', 'email'] then
    perform tecnica.f_error('El reporte del bot no puede traer datos personales de quien reporta (se quedan en el Dell)');
  end if;
  select id into v_id from redes.reportes_externos where canal = p ->> 'canal' and radicado = p ->> 'radicado';
  if found then return v_id; end if;
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, direccion, descripcion, recibido_en)
  values (p ->> 'radicado', p ->> 'canal', p ->> 'tipo', (p ->> 'lat')::numeric, (p ->> 'lon')::numeric, p ->> 'direccion', p ->> 'descripcion',
          coalesce((p ->> 'recibido_en')::timestamptz, clock_timestamp()))
  returning id into v_id;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, autor) values (v_id, 'recibido', 'bot:' || (p ->> 'canal'));
  return v_id;
end $f$;

-- Convertir un reporte del bot en daño o falla (supervisor o administrador; la bandeja va en el Corte 4).
-- p_datos: {clase, tipo, sistema, activo | no_identificado, riesgo, causa_clase?, motivo?}. El daño queda enlazado al radicado y toma
-- la ubicación (o la del activo, si el reporte solo trae dirección), la hora de recepción como detectado y la descripción del reporte.
create function public.geoportal_redes_reporte_convertir(p_solicitante text, p_reporte uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare p record; r redes.v_reporte_externo%rowtype; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tipo redes.tipos_dano%rowtype; v_act redes.activo_vigente_mat%rowtype;
        v_id uuid := gen_random_uuid(); v_cons bigint; v_codigo text; v_lat numeric; v_lon numeric; v_noid text; v_pto geometry;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador convierten reportes del bot' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('redes.reporte.' || p_reporte::text));
  select * into r from redes.v_reporte_externo where id = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte', 'P0002'); end if;
  if r.ultimo_evento in ('convertido', 'descartado') then perform tecnica.f_error(format('Ese reporte ya está %s', r.ultimo_evento)); end if;
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found or v_tipo.clase is distinct from d ->> 'clase' then perform tecnica.f_error('Elija qué pasó'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') or not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error('Elija un sistema que corresponda al tipo'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado or v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo no existe, está retirado o no es de ese sistema'); end if;
  else
    v_noid := coalesce(nullif(btrim(coalesce(d ->> 'no_identificado', '')), ''), 'Reporte del bot ' || r.radicado);
  end if;
  if r.lat is not null then v_lat := r.lat; v_lon := r.lon;
  elsif v_act.activo_id is not null then
    v_pto := case when GeometryType(v_act.geom) = 'POINT' then v_act.geom else ST_PointOnSurface(v_act.geom) end;
    v_lat := round(ST_Y(v_pto)::numeric, 6); v_lon := round(ST_X(v_pto)::numeric, 6);
  else perform tecnica.f_error('El reporte no trae ubicación: elija el activo para ubicar el daño');
  end if;
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, fuera_de_zona, t_detectado,
         riesgo, causa_clase, descripcion, origen, reporte_externo_id, autor)
  values (v_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_act.activo_id, v_noid, v_lat, v_lon, case when r.lat is not null then 'bot' else 'activo' end,
          v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max'),
          least(r.recibido_en, clock_timestamp()), d ->> 'riesgo', 'desconocida',
          left('Reporte del bot ' || r.radicado || ' (' || r.tipo_bot || ')' || coalesce(': ' || r.descripcion, '') || coalesce(' · ' || r.direccion, ''), 1000),
          'bot', p_reporte, p.email);
  insert into redes.reporte_externo_eventos (reporte_id, tipo, dano_id, motivo, autor)
  values (p_reporte, 'convertido', v_id, nullif(btrim(coalesce(d ->> 'motivo', '')), ''), p.email);
  perform tecnica.f_auditar(p.email, 'redes_reporte_convertir', r.radicado, jsonb_build_object('dano', v_codigo, 'tipo', v_tipo.codigo), null);
  return jsonb_build_object('reporte', r.radicado, 'dano_id', v_id, 'dano_codigo', v_codigo, 'estado_bot', 'en_atencion');
end $f$;

create function public.geoportal_redes_reporte_descartar(p_solicitante text, p_reporte uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record; r redes.v_reporte_externo%rowtype;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador descartan reportes del bot' using errcode = '42501'; end if;
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo del descarte (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.reporte.' || p_reporte::text));
  select * into r from redes.v_reporte_externo where id = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte', 'P0002'); end if;
  if r.ultimo_evento in ('convertido', 'descartado') then perform tecnica.f_error(format('Ese reporte ya está %s', r.ultimo_evento)); end if;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor) values (p_reporte, 'descartado', btrim(p_motivo), p.email);
  perform tecnica.f_auditar(p.email, 'redes_reporte_descartar', r.radicado, jsonb_build_object('motivo', btrim(p_motivo)), null);
  return jsonb_build_object('reporte', r.radicado, 'estado_bot', 'descartado');
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 30 — SEMILLA: catálogos del daño (de la maqueta Dano.dc.html) y parámetros
-- =====================================================================
insert into redes.tipos_dano (codigo, clase, nombre, sistemas, pide_rotura, orden) values
  ('fuga', 'dano', 'Fuga o tubería rota', array['acueducto'], true, 1),
  ('valvula_danada', 'dano', 'Válvula dañada', array['acueducto'], true, 2),
  ('hundimiento', 'dano', 'Hundimiento o colapso', array['acueducto', 'alcantarillado'], false, 3),
  ('rebose', 'dano', 'Rebose de alcantarillado', array['alcantarillado'], false, 4),
  ('tubo_roto_alc', 'dano', 'Tubo roto o colapsado', array['alcantarillado'], false, 5),
  ('tapa', 'dano', 'Tapa o rejilla', array['alcantarillado'], false, 6),
  ('otro_dano', 'dano', 'Otro daño', array['acueducto', 'alcantarillado'], false, 9),
  ('bombeo', 'falla', 'Falla de bombeo', array['acueducto', 'alcantarillado'], false, 11),
  ('electrica', 'falla', 'Falla eléctrica', array['acueducto', 'alcantarillado'], false, 12),
  ('valvula_no_opera', 'falla', 'Válvula que no opera', array['acueducto'], false, 13),
  ('obstruccion', 'falla', 'Obstrucción', array['alcantarillado'], false, 14),
  ('sensor', 'falla', 'Sensor o equipo', array['acueducto', 'alcantarillado'], false, 15),
  ('otra_falla', 'falla', 'Otra falla', array['acueducto', 'alcantarillado'], false, 19);
insert into redes.tipos_rotura (codigo, nombre, orden) values ('fisura', 'Fisura', 1), ('union', 'Fuga en la unión', 2), ('parcial', 'Rotura parcial', 3), ('total', 'Rotura total', 4);
insert into redes.causas (codigo, nombre, orden) values
  ('desgaste', 'Desgaste o vejez de la tubería', 1), ('sobrepresion', 'Sobrepresión o golpe de ariete', 2), ('falla_material', 'Falla del material o de la unión', 3),
  ('asentamiento', 'Asentamiento del terreno', 4), ('obstruccion', 'Obstrucción (grasas, sedimentos, basura)', 5), ('otra', 'Otra', 9);
insert into redes.tipos_tercero (codigo, nombre, orden) values
  ('obra_alcaldia', 'Obra de la alcaldía', 1), ('contratista_obra', 'Contratista de obra', 2), ('empresa_servicio', 'Empresa de otro servicio (gas, energía, telecomunicaciones)', 3),
  ('particular', 'Particular', 4), ('vehiculo', 'Vehículo', 5), ('vandalismo', 'Vandalismo', 6);
insert into redes.marcas_riesgo (codigo, nombre, orden) values
  ('via', 'Hueco o hundimiento en la vía', 1), ('personas', 'Riesgo para personas o vehículos', 2), ('contaminacion', 'Posible contaminación del agua', 3),
  ('usuario_sensible', 'Afecta un hospital, colegio u otro usuario sensible', 4);
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('dano_dias_atras_max', 7, 'días', 1, 60, 'Cuánto atrás puede ser la hora de detección de un daño (D-25)'),
  ('min_fotos_dano', 1, 'fotos', 0, 10, 'Fotos mínimas de un daño o falla (al menos una del daño)'),
  ('max_fotos_dano', 6, 'fotos', 1, 10, 'Fotos máximas de un daño o falla'),
  ('max_bytes_foto_dano', 1572864, 'bytes', 102400, 2097152, 'Tope fino de cada foto del daño (1,5 MB); el bucket admite hasta 5 MB por los PDF'),
  ('mini_zoom_min', 15, 'zoom', 12, 18, 'Desde qué zoom el minimapa pide la red'),
  ('mini_zoom_acc', 17, 'zoom', 14, 20, 'Desde qué zoom el minimapa muestra los accesorios')
on conflict (clave) do nothing;   -- si una reversa anterior los conservó (redes.parametros no deja borrar filas), se reutilizan con su valor
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas de redes: RLS activa sin políticas y ningún privilegio para la API. Funciones internas: nadie de la API.
-- RPC public.geoportal_redes_* nuevas: solo execute a service_role. (Las del 1a no cambian.)
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
do $$
declare t record; f record;
begin
  for t in select c.relname from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity loop
    execute format('alter table redes.%I enable row level security', t.relname);
  end loop;
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
           ('geoportal_redes_formulario_dano', 'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano', 'geoportal_redes_activo_buscar',
            'geoportal_redes_tramo_nodos', 'geoportal_redes_mvt', 'geoportal_redes_reporte_convertir', 'geoportal_redes_reporte_descartar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
commit;
