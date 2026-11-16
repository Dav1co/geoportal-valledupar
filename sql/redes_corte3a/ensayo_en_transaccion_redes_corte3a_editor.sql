begin;
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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '06ecefcf2922e724e1be5546b87a5510' then
    raise exception 'Las funciones de redes no son las del Corte 2 (o el Corte 3a ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> '6c5d9335e3d49eddaf7149a1b8731ef6' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'd97fa858302da7febe1cb82270e24185' then
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
  resuelve_dano        boolean not null default false,                              -- «Con esta queda resuelto el daño» (David, respuesta 2 al 3a)
  autor                text not null,
  registrado_en        timestamptz not null default clock_timestamp(),
  check ((nace_de = 'dano') = (dano_id is not null)),
  check (not resuelve_dano or nace_de = 'dano'),
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 20 — VISTAS: v_intervencion (estado, activo vigente, recursos y evidencia), fuentes vigentes,
-- bandeja de no identificados, v_dano (con el activo asociado) y la epicrisis con las intervenciones.
-- PROPUESTA. No se ha ejecutado en la base real. Nada se escribe calculado: todo se deriva en las vistas.
-- =====================================================================

-- Daño (Corte 2) con UN cambio: el activo vigente es el del último «asociar_activo» (bandeja de no identificados) o, si no hay, el del reporte.
-- Mismas columnas, en el mismo orden. La reversa deja el texto del Corte 2.
create or replace view redes.v_dano as
with b0 as (
  select d.*, coalesce((select e.activo_id from redes.dano_eventos e where e.dano_id = d.id and e.tipo = 'asociar_activo' order by e.id desc limit 1), d.activo_id) as activo_vig
    from redes.danos d),
b as (
  select d.*, tm.t_inicio_reparacion, tm.t_restablecido,
         (select e.tipo = 'ocultar' from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('ocultar', 'reincluir') order by e.id desc limit 1) as ev_oculto,
         (select e.tipo from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('atendido', 'reabrir', 'en_atencion') order by e.id desc limit 1) as ev_estado,
         (select a.codigo from redes.activos a where a.id = d.activo_vig) as activo_codigo,
         (select v.diametro_mm from redes.activo_vigente_mat v where v.activo_id = d.activo_vig) as diametro_mm
    from b0 d join redes.v_dano_tiempos tm on tm.dano_id = d.id),
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
       c.sistema, c.activo_vig as activo_id, c.activo_codigo, c.no_ident_que_es, c.lat, c.lon, c.geom, c.ubicacion_origen, c.precision_m, c.fuera_de_zona,
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

-- Fuentes vigentes de cada intervención: las de su última versión.
create view redes.v_intervencion_fuentes as
select f.*
  from redes.intervencion_fuentes f
 where f.version = (select max(x.version) from redes.intervencion_fuentes x where x.intervencion_id = f.intervencion_id);

-- Intervención con lo derivado:
--   activo vigente = el del último «asociar_activo» o, si no hay, el del formulario (o el que creó la inversión);
--   estado = último de programada, en_ejecucion, cerrada o anulada (flujo A: siempre «cerrada» al crearse); oculta = último ocultar/reincluir;
--   recursos = «por_completar» mientras alguna fuente vigente no tenga ni valor ni porcentaje (el operario solo marca quién aporta);
--   sin_evidencia = no tiene ninguna foto (solo puede pasar si la registró un supervisor o el administrador, con su motivo).
create view redes.v_intervencion as
with b as (
  select i.*, coalesce((select e.activo_id from redes.intervencion_eventos e where e.intervencion_id = i.id and e.tipo = 'asociar_activo' order by e.id desc limit 1), i.activo_id) as activo_vig,
         (select e.tipo from redes.intervencion_eventos e where e.intervencion_id = i.id and e.tipo in ('programada', 'en_ejecucion', 'cerrada', 'anulada') order by e.id desc limit 1) as ev_estado,
         coalesce((select e.tipo = 'ocultar' from redes.intervencion_eventos e where e.intervencion_id = i.id and e.tipo in ('ocultar', 'reincluir') order by e.id desc limit 1), false) as oculta,
         (select count(*) from redes.intervencion_archivos a where a.intervencion_id = i.id and a.clase <> 'documento')::integer as fotos,
         (select count(*) from redes.intervencion_archivos a where a.intervencion_id = i.id and a.clase = 'documento')::integer as documentos
    from redes.intervenciones i)
select b.id, b.codigo, b.nace_de, b.dano_id, (select d.codigo from redes.danos d where d.id = b.dano_id) as dano_codigo,
       b.tipo_codigo, (select t.nombre from redes.tipos_intervencion t where t.codigo = b.tipo_codigo) as tipo_nombre, b.inversion_modo,
       b.sistema, b.activo_vig as activo_id, (select a.codigo from redes.activos a where a.id = b.activo_vig) as activo_codigo, b.activo_creado,
       b.no_ident_que_es, b.lat, b.lon, b.geom, b.ubicacion_origen, b.precision_m, b.fuera_de_zona,
       b.t_inicio, b.t_fin, extract(epoch from (b.t_fin - b.t_inicio))::bigint as duracion_s, b.inicio_en, b.inicio_origen, b.descripcion,
       b.ejecutor, b.contratista_id, coalesce((select c.nombre from redes.contratistas c where c.id = b.contratista_id), b.contratista_nombre) as contratista,
       b.contrato_orden, b.companeros, b.sin_evidencia_motivo, b.resuelve_dano, b.autor, b.registrado_en,
       case when b.oculta then 'oculta' else coalesce(b.ev_estado, 'cerrada') end as estado,
       b.fotos, b.documentos, b.fotos = 0 as sin_evidencia,
       case when exists (select 1 from redes.v_intervencion_fuentes f where f.intervencion_id = b.id and f.valor is null and f.porcentaje is null) then 'por_completar' else 'completos' end as recursos,
       (select array_agg(coalesce(f.entidad, e.nombre) order by f.n) from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo
         where f.intervencion_id = b.id) as aportantes,
       (select count(*) from redes.intervencion_activos x where x.intervencion_id = b.id)::integer as tambien
  from b;

-- Bandeja de «activo no identificado» (para el supervisor): intervenciones y daños sin activo vigente, que no estén ocultos.
create view redes.v_no_identificados as
select 'intervencion'::text as clase, i.id, i.codigo, i.sistema, i.no_ident_que_es as que_es, i.lat, i.lon, i.geom, i.t_fin as cuando, i.tipo_nombre as resumen, i.estado, i.autor, i.registrado_en
  from redes.v_intervencion i
 where i.activo_id is null and i.estado <> 'oculta'
union all
select 'dano', d.id, d.codigo, d.sistema, d.no_ident_que_es, d.lat, d.lon, d.geom, d.t_detectado, d.tipo_nombre, d.estado, d.autor, d.registrado_en
  from redes.v_dano d
 where d.activo_id is null and d.estado <> 'oculto';

-- Epicrisis: la del Corte 2 (altas, versiones, eventos, componentes, daños y fallas) MÁS las intervenciones (clase «intervencion»), en el activo
-- principal y en cada «también intervenido». El ref_id es el número del código (ITV-000123 → 123), para paginar con el mismo cursor.
-- Mismas columnas que en el Corte 2. La reversa deja el texto del Corte 2.
create or replace view redes.v_epicrisis as
select v.activo_id, v.creado_en as cuando, case when v.version = 1 then 'alta' else 'version' end as clase, v.id as ref_id,
       case when v.version = 1 then 'Alta del activo' else 'Versión ' || v.version end
         || case when v.carga_id is not null then ' (carga ' || v.carga_id || ')'
                 when v.version = 1 and exists (select 1 from redes.activos x where x.id = v.activo_id and x.origen_alta = 'intervencion')
                   then coalesce(' (inversión ' || (select i.codigo from redes.intervenciones i where i.activo_id = v.activo_id and i.activo_creado limit 1) || ')', ' (intervención)')
                 else ' (ficha)' end as resumen,
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
         || case when d.perdida_m3 is not null then ' · pérdida ≈ ' || d.perdida_m3 || ' m³' else '' end
         || case when not exists (select 1 from redes.dano_fotos f where f.dano_id = d.id) then ' · sin evidencia fotográfica' else '' end,
       case d.estado when 'reportado' then 'Reportado' when 'en_atencion' then 'En atención' when 'atendido' then 'Atendido' else 'Oculto' end,
       d.autor
  from redes.v_dano d
 where d.activo_id is not null and d.estado <> 'oculto'
union all
-- Intervenciones: en el activo principal…
select i.activo_id, i.t_fin, 'intervencion', substring(i.codigo from 5)::bigint,
       i.codigo || ' · ' || i.tipo_nombre
         || case i.inversion_modo when 'nuevo' then ' (activo nuevo)' when 'mejora' then ' (mejora)' else '' end
         || case when i.dano_codigo is not null then ' · atiende ' || i.dano_codigo || case when i.resuelve_dano then ' (lo resuelve)' else ' (sigue abierto)' end else ' · programada o mejora' end
         || case i.ejecutor when 'emdupar' then ' · EMDUPAR' else ' · contratista' || coalesce(' ' || i.contratista, '') end
         || ' · duración ' || (i.duracion_s / 3600) || ' h ' || lpad(((i.duracion_s % 3600) / 60)::text, 2, '0') || ' min'
         || case when i.tambien > 0 then ' · ' || i.tambien || ' activo(s) más' else '' end
         || case when i.sin_evidencia then ' · sin evidencia fotográfica' else ' · ' || i.fotos || ' foto(s)' end,
       case i.estado when 'cerrada' then 'Cerrada' when 'anulada' then 'Anulada' when 'programada' then 'Programada' when 'en_ejecucion' then 'En ejecución' else 'Oculta' end,
       i.autor
  from redes.v_intervencion i
 where i.activo_id is not null and i.estado <> 'oculta'
union all
-- … y en cada activo también intervenido
select x.activo_id, i.t_fin, 'intervencion', substring(i.codigo from 5)::bigint,
       i.codigo || ' · ' || i.tipo_nombre || ' · también intervenido' || coalesce(' (principal ' || i.activo_codigo || ')', ''),
       case i.estado when 'cerrada' then 'Cerrada' when 'anulada' then 'Anulada' when 'programada' then 'Programada' when 'en_ejecucion' then 'En ejecución' else 'Oculta' end,
       i.autor
  from redes.intervencion_activos x join redes.v_intervencion i on i.id = x.intervencion_id
 where i.estado <> 'oculta' and x.activo_id is distinct from i.activo_id;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 25 — RPC: formulario, preparar y crear la intervención (flujo A, cierre del daño, inversión que crea
-- un activo); daños abiertos cercanos; bandeja de no identificados y «asociar activo»; recursos del supervisor; y el daño sin fotos.
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Captura: tecnica.f_autorizar_captura(correo, 'mantenimiento') — la clave ya existe (00_inspeccion): el operador necesita el formulario
-- asignado en Personal; supervisor y administrador pasan siempre. Supervisión: el perfil del 1b (hasta el Corte 4, ver_dashboard_tecnico).
-- =====================================================================

-- ---------- Ayudantes internos (nadie de la API los ejecuta) ----------
-- Supervisor o administrador de Técnica; si no, 42501.
create function redes.f_supervisor(p_solicitante text, p_que text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador %', p_que using errcode = '42501'; end if;
  return p.email;
end $f$;

-- Reconstruye UNA fila de activo_vigente_mat (alta por inversión, asociar, edición de la ficha): no se recalcula la tabla entera.
create function redes.f_mat_refrescar_uno(p_activo bigint) returns void
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
begin
  delete from redes.activo_vigente_mat where activo_id = p_activo;
  insert into redes.activo_vigente_mat (activo_id, codigo, prefijo, sistema, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m,
         profundidad_m, fecha_instalacion, estado_codigo, cuenta_vigente, punteado, retirado, oculto, capa_codigo, llave_capa, codigo_anterior, carga_id)
  select activo_id, codigo, prefijo, sistema, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m,
         profundidad_m, fecha_instalacion, estado_codigo, cuenta_vigente, punteado, retirado, oculto, capa_codigo, llave_capa, codigo_anterior, carga_id
    from redes.v_activo_vigente where activo_id = p_activo;
end $f$;

-- Alta de un activo que crea una intervención (inversión, activo nuevo): código propio, versión 1 sin carga, «por verificar» y su origen.
-- La topología (nodos) y el enlace con los contratos se completan cuando el supervisor lo verifica o llega en una carga (Cortes 4 y 5).
create function redes.f_activo_crear(p_prefijo text, p_geom geometry, p_clase text, p_material text, p_diametro numeric, p_nombre text, p_fecha date,
                                     p_atributos jsonb, p_origen text, p_aportante text, p_autor text, p_motivo text) returns bigint
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare v_cons bigint; v_cod text; v_id bigint; v_long numeric; v_attr jsonb := coalesce(p_atributos, '{}'::jsonb);
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  if v_cons is null then perform tecnica.f_error('Ese tipo de activo no tiene consecutivo'); end if;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'intervencion', p_autor) returning id into v_id;
  v_long := case when GeometryType(p_geom) in ('LINESTRING', 'MULTILINESTRING') then round(ST_Length(p_geom::geography)::numeric, 2) end;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, longitud_m, fecha_instalacion, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, p_nombre, p_clase, p_material, p_diametro, v_long, p_fecha, 'en_operacion', v_attr,
          redes.f_huella(p_geom, jsonb_build_object('p', p_prefijo, 'n', p_nombre, 'c', p_clase, 'e', null, 'm', p_material, 'd', p_diametro, 'l', v_long,
                                                    'pr', null, 'ca', null, 's', 'en_operacion', 'ant', null, 'a', v_attr)), p_autor);
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_id, 'por_verificar', p_motivo, p_autor);
  insert into redes.activo_origen (activo_id, version, origen, aportante_codigo, nota, autor) values (v_id, 1, p_origen, p_aportante, left(p_motivo, 500), p_autor);
  perform redes.f_mat_refrescar_uno(v_id);
  perform redes.f_subir_tesela((select sistema from redes.tipos_activo where prefijo = p_prefijo));
  return v_id;
end $f$;

-- Fuentes de los recursos (D-8) → lista limpia {n, aportante, entidad, valor, porcentaje, soporte}.
--   p_con_valores = falso (operario): solo quién aporta; si trae valor, porcentaje o soporte, se rechaza.
--   p_exigir_valor (el supervisor completa): cada fuente lleva su valor o su porcentaje. Los porcentajes no suman más de 100.
create function redes.f_fuentes_validas(p jsonb, p_con_valores boolean, p_exigir_valor boolean) returns jsonb
language plpgsql stable set search_path to 'redes', 'tecnica', 'pg_temp' as $f$
declare f jsonb; v_out jsonb := '[]'::jsonb; v_n integer := 0; v_pct numeric := 0; v_ap text; v_ent text; v_val numeric; v_por numeric; v_sop text; v_vistos text[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then perform tecnica.f_error('Marque quién aporta los recursos (al menos una fuente)'); end if;
  if jsonb_array_length(p) > 10 then perform tecnica.f_error('Hasta 10 fuentes de recursos'); end if;
  for f in select e from jsonb_array_elements(p) e loop
    if jsonb_typeof(f) <> 'object' then perform tecnica.f_error('Las fuentes de los recursos no son válidas'); end if;
    v_ap := f ->> 'aportante';
    if not exists (select 1 from redes.entidades_aportantes where codigo = v_ap and activo) then perform tecnica.f_error('Una de las fuentes de los recursos no existe'); end if;
    v_ent := nullif(btrim(coalesce(f ->> 'entidad', '')), '');
    if v_ap = 'otro' and v_ent is null then perform tecnica.f_error('Diga cuál es la otra entidad que aporta'); end if;
    if v_ent is not null and length(v_ent) not between 2 and 120 then perform tecnica.f_error('El nombre de la entidad lleva de 2 a 120 caracteres'); end if;
    if (v_ap || '|' || coalesce(lower(v_ent), '')) = any (v_vistos) then perform tecnica.f_error('Hay una fuente de recursos repetida'); end if;
    v_vistos := v_vistos || (v_ap || '|' || coalesce(lower(v_ent), ''));
    v_val := (f ->> 'valor')::numeric; v_por := (f ->> 'porcentaje')::numeric; v_sop := nullif(btrim(coalesce(f ->> 'soporte', '')), '');
    if not p_con_valores and (v_val is not null or v_por is not null or v_sop is not null) then
      perform tecnica.f_error('El valor, el porcentaje y el soporte de los recursos los pone el supervisor');
    end if;
    if v_val is not null and (v_val < 0 or v_val >= 100000000000000) then perform tecnica.f_error('El valor de una fuente no es válido'); end if;
    if v_por is not null and (v_por <= 0 or v_por > 100) then perform tecnica.f_error('El porcentaje de una fuente va de 0 a 100'); end if;
    if p_exigir_valor and v_val is null and v_por is null then perform tecnica.f_error('Cada fuente lleva su valor o su porcentaje'); end if;
    if v_sop is not null and length(v_sop) not between 2 and 200 then perform tecnica.f_error('El soporte lleva de 2 a 200 caracteres'); end if;
    v_pct := v_pct + coalesce(v_por, 0); v_n := v_n + 1;
    v_out := v_out || jsonb_build_object('n', v_n, 'aportante', v_ap, 'entidad', v_ent, 'valor', v_val, 'porcentaje', v_por, 'soporte', v_sop);
  end loop;
  if v_pct > 100 then perform tecnica.f_error('Los porcentajes de las fuentes suman más de 100'); end if;
  return v_out;
end $f$;

-- ¿El daño se puede atender con esta intervención? Abierto, del mismo sistema y del activo (o de uno también intervenido) o cercano.
create function redes.f_dano_elegible(p_dano redes.v_dano, p_sistema text, p_activos bigint[], p_pto geometry) returns boolean
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
  select coalesce(p_dano.estado in ('reportado', 'en_atencion') and p_dano.sistema = p_sistema
     and (coalesce(p_dano.activo_id = any (p_activos), false)
          or ST_DWithin(p_dano.geom::geography, p_pto::geography, redes.f_param('itv_radio_danos_m'))
          or exists (select 1 from redes.activo_vigente_mat m where m.activo_id = any (p_activos) and ST_DWithin(m.geom::geography, p_dano.geom::geography, redes.f_param('itv_radio_danos_m')))), false) $f$;

-- ---------- Formulario: catálogos y reglas para la pantalla ----------
create function public.geoportal_redes_formulario_intervencion(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_perfil text := tecnica.f_perfil(v_email);
begin
  return jsonb_build_object(
    'perfil', v_perfil,
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'admite_dano', admite_dano, 'es_inversion', es_inversion) order by orden) from redes.tipos_intervencion where activo),
    'aportantes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.entidades_aportantes where activo),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by nombre) from redes.contratistas where activo), '[]'::jsonb),
    'unidades', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.unidades_material where activo),
    -- tipos de activo que puede crear una inversión «activo nuevo», con sus clases (y si la clase es obligatoria)
    'tipos_nuevo', (select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema, 'geometria', t.geometria,
                       'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden) from redes.clases_activo c where c.prefijo = t.prefijo), '[]'::jsonb),
                       'clase_obligatoria', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean),
                       'lleva_diametro', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'diametro_mm'))
                     order by t.orden)
                      from redes.v_tipo_visible t where t.sistema in ('acueducto', 'alcantarillado') and t.geometria in ('punto', 'linea')),
    'materiales', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.materiales),
    -- el operario conserva el tope de días y de horas; el supervisor y el administrador registran las obras largas sin ese tope (David, respuesta 1 al 3a)
    'reglas', jsonb_build_object('dias_atras_max', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_dias_atras_max') end,
                                 'max_horas', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_max_horas') end,
                                 'min_fotos', case when v_perfil in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_itv') end,
                                 'puede_sin_fotos', v_perfil in ('admin', 'supervisor'), 'pone_valores', v_perfil in ('admin', 'supervisor'),
                                 'max_fotos', redes.f_param('max_fotos_itv'), 'max_documentos', redes.f_param('max_docs_itv'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_itv'), 'max_bytes_documento', redes.f_param('max_bytes_doc_itv'),
                                 'max_horas_inicio', tecnica.f_max_horas_inicio(), 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'),
                                 'radio_danos_m', redes.f_param('itv_radio_danos_m'), 'max_tambien', redes.f_param('itv_max_activos_tambien'),
                                 'max_materiales', redes.f_param('itv_max_materiales'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'ahora', clock_timestamp());
end $f$;

-- ---------- Daños abiertos que puede atender (del activo, de los también intervenidos o cercanos). La posición no se guarda. ----------
create function public.geoportal_redes_danos_abiertos(p_solicitante text, p_sistema text, p_activo text default null, p_lat numeric default null, p_lon numeric default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_id bigint; v_ref geometry; v_radio numeric := redes.f_param('itv_radio_danos_m');
begin
  if coalesce(p_sistema, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then
    v_id := redes.f_buscar_activo(p_activo);
    select geom into v_ref from redes.activo_vigente_mat where activo_id = v_id;
  elsif p_lat is not null and p_lon is not null and p_lat between -90 and 90 and p_lon between -180 and 180 then
    v_ref := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326);
  else perform tecnica.f_error('Elija primero el activo o marque el punto');
  end if;
  return jsonb_build_object('radio_m', v_radio, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
                                        't_detectado', x.t_detectado, 'estado', x.estado, 'mismo_activo', x.mismo, 'distancia_m', x.dist) order by x.mismo desc, x.dist, x.t_detectado desc)
      from (select d.codigo, d.clase, d.tipo_nombre, d.activo_codigo, d.no_ident_que_es, d.t_detectado, d.estado,
                   coalesce(d.activo_id = v_id, false) as mismo, round(ST_Distance(d.geom::geography, v_ref::geography)::numeric, 0) as dist
              from redes.v_dano d
             where d.estado in ('reportado', 'en_atencion') and d.sistema = p_sistema
               and (d.activo_id = v_id or ST_DWithin(d.geom::geography, v_ref::geography, v_radio))
             order by 8 desc, 9, d.t_detectado desc limit 10) x), '[]'::jsonb));
end $f$;

-- ---------- Preparar: reserva el id y las rutas de las fotos (1…F, .jpg) y de los documentos (F+1…F+D, .pdf) ----------
create function public.geoportal_redes_preparar_intervencion(p_solicitante text, p_fotos integer, p_documentos integer default 0)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_min integer; v_max integer := redes.f_param('max_fotos_itv')::integer;
        v_maxd integer := redes.f_param('max_docs_itv')::integer; v_d integer := coalesce(p_documentos, 0);
begin
  v_min := case when tecnica.f_perfil(v_email) in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_itv')::integer end;
  if p_fotos is null or p_fotos < v_min or p_fotos > v_max then perform tecnica.f_error(format('Una intervención lleva de %s a %s fotos', v_min, v_max)); end if;
  if v_d < 0 or v_d > v_maxd then perform tecnica.f_error(format('Se adjuntan hasta %s documentos', v_maxd)); end if;
  insert into redes.intervencion_preparaciones (intervencion_id, autor, fotos, documentos) values (v_id, v_email, p_fotos, v_d);
  return jsonb_build_object('intervencion_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_itv')::bigint,
    'max_bytes_documento', redes.f_param('max_bytes_doc_itv')::bigint,
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'intervenciones/' || v_mes || '/' || v_id::text || '/' || n || '.jpg', 'tipo_mime', 'image/jpeg') order by n)
                         from generate_series(1, p_fotos) n), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('n', p_fotos + n, 'ruta', 'intervenciones/' || v_mes || '/' || v_id::text || '/' || (p_fotos + n) || '.pdf', 'tipo_mime', 'application/pdf') order by n)
                              from generate_series(1, v_d) n), '[]'::jsonb));
end $f$;

-- ---------- Crear la intervención (flujo A, D-6: queda «cerrada»). Una sola transacción. Hora oficial = servidor; autor = solicitante verificado. ----------
-- p_datos: {nace_de, dano, tipo, inversion_modo, sistema, activo | no_identificado | nuevo{prefijo, clase, material, diametro_mm, nombre, puntos[[lat, lon]…]},
--           lat, lon, precision_m, ubicacion_origen, t_inicio, t_fin, inicio_dispositivo, descripcion, materiales[{material, cantidad, unidad}],
--           ejecutor, contratista, contratista_nombre, contrato_orden, companeros, tambien[códigos], fuentes[{aportante, entidad, valor, porcentaje, soporte}],
--           sin_evidencia_motivo, archivos[{n, clase, ruta}]}
-- Si nace de un daño abierto: el daño recibe sus tiempos de reparación (inicio y fin del trabajo) y queda «atendido» con el código de la intervención.
create function public.geoportal_redes_crear_intervencion(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_super boolean; d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_intervencion%rowtype; v_tipo redes.tipos_intervencion%rowtype; v_sis text; v_modo text;
  v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text; v_nuevo jsonb; v_tn redes.v_tipo_visible%rowtype; v_geom_nuevo geometry;
  v_clase_n text; v_mat_n text; v_diam_n numeric; v_nom_n text; v_pts jsonb; v_p jsonb; v_lat numeric; v_lon numeric; v_fuera boolean;
  v_t_ini timestamptz; v_t_fin timestamptz; v_inicio timestamptz; v_desc text := btrim(coalesce(d ->> 'descripcion', ''));
  v_dano redes.v_dano%rowtype; v_tambien bigint[] := '{}'; v_x text; v_xid bigint; v_mats jsonb := coalesce(d -> 'materiales', '[]'::jsonb); v_m jsonb;
  v_fuentes jsonb; v_arch jsonb := coalesce(d -> 'archivos', '[]'::jsonb); v_ref jsonb := '[]'::jsonb; v_nf integer := 0; v_nd integer := 0; v_n integer;
  v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_prep redes.intervencion_preparaciones%rowtype; v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_cons bigint; v_codigo text; v_ctr bigint; v_ctr_nom text; v_orden text := nullif(btrim(coalesce(d ->> 'contrato_orden', '')), '');
  v_comp text := nullif(btrim(coalesce(d ->> 'companeros', '')), ''); v_pto geometry; v_creado boolean := false; v_origen text; v_aport text; v_cod_nuevo text;
  v_dano_estado text; v_resuelve boolean := coalesce((p_datos ->> 'resuelve_dano')::boolean, false);
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador de la intervención: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_intervencion where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'activo_creado', v_prev.activo_creado, 'dano', v_prev.dano_codigo, 'sin_evidencia', v_prev.sin_evidencia, 'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
  end if;
  select * into v_prep from redes.intervencion_preparaciones where intervencion_id = p_id and autor = v_email;
  if not found then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos de la intervención no son válidos'); end if;
  v_super := tecnica.f_perfil(v_email) in ('admin', 'supervisor');

  -- 1. de dónde nace y tipo
  if coalesce(d ->> 'nace_de', '') not in ('programada', 'dano') then perform tecnica.f_error('Elija de dónde nace: programada o mejora, o daño o falla'); end if;
  select * into v_tipo from redes.tipos_intervencion where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija el tipo de intervención'); end if;
  if d ->> 'nace_de' = 'dano' and not v_tipo.admite_dano then perform tecnica.f_error(format('«%s» no atiende un daño: elija correctivo, reparación o reposición', v_tipo.nombre)); end if;
  v_modo := d ->> 'inversion_modo';
  if v_tipo.es_inversion and coalesce(v_modo, '') not in ('nuevo', 'mejora') then perform tecnica.f_error('Diga qué tipo de inversión es: activo nuevo o mejora de un activo existente'); end if;
  if not v_tipo.es_inversion then v_modo := null; end if;
  v_sis := d ->> 'sistema';
  if coalesce(v_sis, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;

  -- 2. activo: el elegido, «no identificado» o el que crea la inversión
  if v_modo = 'nuevo' then
    v_nuevo := d -> 'nuevo';
    if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null or d ->> 'no_identificado' is not null then perform tecnica.f_error('Una inversión en un activo nuevo no lleva un activo existente'); end if;
    if v_nuevo is null or jsonb_typeof(v_nuevo) <> 'object' then perform tecnica.f_error('Diga qué activo nuevo se construyó'); end if;
    select * into v_tn from redes.v_tipo_visible where prefijo = upper(coalesce(v_nuevo ->> 'prefijo', '')) and sistema = v_sis and geometria in ('punto', 'linea');
    if not found then perform tecnica.f_error('Elija el tipo del activo nuevo (del mismo sistema)'); end if;
    v_clase_n := nullif(v_nuevo ->> 'clase', '');
    if v_clase_n is not null and not exists (select 1 from redes.clases_activo where prefijo = v_tn.prefijo and codigo = v_clase_n) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
    if v_clase_n is null and exists (select 1 from jsonb_array_elements(v_tn.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
      perform tecnica.f_error(format('Elija la clase del activo nuevo (%s)', v_tn.nombre_visible));
    end if;
    v_mat_n := nullif(v_nuevo ->> 'material', '');
    if v_mat_n is not null and not exists (select 1 from redes.materiales where codigo = v_mat_n) then perform tecnica.f_error('Ese material no existe'); end if;
    v_diam_n := (v_nuevo ->> 'diametro_mm')::numeric;
    if v_diam_n is not null and (v_diam_n <= 0 or v_diam_n > 5000) then perform tecnica.f_error('El diámetro va de 1 a 5.000 mm'); end if;
    v_nom_n := nullif(btrim(coalesce(v_nuevo ->> 'nombre', '')), '');
    if v_nom_n is not null and length(v_nom_n) > 120 then perform tecnica.f_error('El nombre del activo nuevo admite hasta 120 caracteres'); end if;
    v_pts := v_nuevo -> 'puntos';
    if v_pts is null or jsonb_typeof(v_pts) <> 'array' then perform tecnica.f_error('Marque en el mapa dónde quedó el activo nuevo'); end if;
    if v_tn.geometria = 'punto' and jsonb_array_length(v_pts) <> 1 then perform tecnica.f_error('Marque un solo punto para el activo nuevo'); end if;
    if v_tn.geometria = 'linea' and jsonb_array_length(v_pts) not between 2 and 50 then perform tecnica.f_error('Marque el inicio y el fin del tramo nuevo'); end if;
    for v_p in select e from jsonb_array_elements(v_pts) e loop
      if jsonb_typeof(v_p) <> 'array' or jsonb_array_length(v_p) <> 2 or (v_p ->> 0)::numeric not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max')
         or (v_p ->> 1)::numeric not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
        perform tecnica.f_error('El activo nuevo debe quedar dentro de Valledupar');
      end if;
    end loop;
    v_geom_nuevo := case when v_tn.geometria = 'punto' then ST_SetSRID(ST_MakePoint((v_pts -> 0 ->> 1)::double precision, (v_pts -> 0 ->> 0)::double precision), 4326)
                         else ST_SetSRID(ST_MakeLine(array(select ST_MakePoint((e ->> 1)::double precision, (e ->> 0)::double precision) from jsonb_array_elements(v_pts) with ordinality x(e, o) order by o)), 4326) end;
    if v_tn.geometria = 'linea' and ST_Length(v_geom_nuevo::geography) < 0.5 then perform tecnica.f_error('El tramo nuevo es demasiado corto: marque el inicio y el fin'); end if;
  elsif nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> v_sis then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación de la intervención: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación de la intervención'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');
  v_pto := ST_SetSRID(ST_MakePoint(v_lon, v_lat), 4326);

  -- activos también intervenidos (mismo sistema, vigentes, sin repetir y distintos del principal)
  if d -> 'tambien' is not null then
    if jsonb_typeof(d -> 'tambien') <> 'array' then perform tecnica.f_error('Los activos también intervenidos no son válidos'); end if;
    if jsonb_array_length(d -> 'tambien') > redes.f_param('itv_max_activos_tambien') then
      perform tecnica.f_error(format('Hasta %s activos también intervenidos', redes.f_param('itv_max_activos_tambien')::integer));
    end if;
    for v_x in select jsonb_array_elements_text(d -> 'tambien') loop
      select activo_id into v_xid from redes.activo_vigente_mat where codigo = upper(btrim(v_x)) and not retirado and sistema = v_sis;
      if v_xid is null then perform tecnica.f_error(format('El activo también intervenido «%s» no existe, está retirado o no es de ese sistema', v_x)); end if;
      if v_xid = v_activo then perform tecnica.f_error('El activo principal no va otra vez en «también intervenidos»'); end if;
      if v_xid = any (v_tambien) then perform tecnica.f_error(format('El activo «%s» está repetido en «también intervenidos»', v_x)); end if;
      v_tambien := v_tambien || v_xid;
    end loop;
  end if;

  -- 3. fechas y horas del trabajo (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio', 'inicio');
  v_t_fin := redes.f_instante(d ->> 't_fin', 'fin');
  if v_t_ini is null or v_t_fin is null then perform tecnica.f_error('Escriba el inicio y el fin de la intervención'); end if;
  if v_t_fin > v_ahora + interval '2 minutes' then perform tecnica.f_error('El fin está en el futuro: la intervención se registra cuando ya se hizo'); end if;
  if v_t_ini > v_t_fin then perform tecnica.f_error('El inicio no puede ser después del fin'); end if;
  -- el tope de días y de horas es del operario; el supervisor y el administrador registran las obras largas desde el escritorio sin él
  if not v_super and v_t_ini < v_ahora - make_interval(days => redes.f_param('itv_dias_atras_max')::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param('itv_dias_atras_max')::integer));
  end if;
  if not v_super and v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: si duró más, la registra el supervisor desde el escritorio', redes.f_param('itv_max_horas')::integer));
  end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- daño que atiende: abierto, del mismo sistema y del activo, de un también intervenido o cercano
  if d ->> 'nace_de' = 'dano' then
    if nullif(btrim(coalesce(d ->> 'dano', '')), '') is null then perform tecnica.f_error('Elija el daño o falla que se atiende'); end if;
    perform pg_advisory_xact_lock(hashtext('redes.dano.' || upper(btrim(d ->> 'dano'))));
    select * into v_dano from redes.v_dano where codigo = upper(btrim(d ->> 'dano'));
    if not found then perform tecnica.f_error('Ese daño no existe'); end if;
    if v_dano.estado not in ('reportado', 'en_atencion') then perform tecnica.f_error(format('El daño %s ya está %s', v_dano.codigo, case v_dano.estado when 'atendido' then 'atendido' else 'oculto' end)); end if;
    if not redes.f_dano_elegible(v_dano, v_sis, array_remove(v_tambien || v_activo, null), v_pto) then
      perform tecnica.f_error(format('El daño %s no es de este activo ni de los cercanos (%s m)', v_dano.codigo, redes.f_param('itv_radio_danos_m')::integer));
    end if;
    if v_dano.t_inicio_reparacion is null and v_t_ini < v_dano.t_detectado then
      perform tecnica.f_error(format('La intervención empezó antes de que se detectara el daño %s: revise las horas', v_dano.codigo));
    end if;
    if v_resuelve and v_dano.t_inicio_reparacion is not null and v_t_fin < v_dano.t_inicio_reparacion then
      perform tecnica.f_error(format('La intervención terminó antes del inicio de la reparación que ya tenía el daño %s', v_dano.codigo));
    end if;
  elsif v_resuelve then
    perform tecnica.f_error('«Con esta queda resuelto el daño» solo va cuando la intervención nace de un daño');
  end if;

  -- 4. qué se hizo y materiales
  if length(v_desc) < 10 or length(v_desc) > 2000 then perform tecnica.f_error('Describa qué se hizo (10 a 2.000 caracteres)'); end if;
  if jsonb_typeof(v_mats) <> 'array' or jsonb_array_length(v_mats) > redes.f_param('itv_max_materiales') then perform tecnica.f_error(format('Hasta %s materiales', redes.f_param('itv_max_materiales')::integer)); end if;
  for v_m in select e from jsonb_array_elements(v_mats) e loop
    if jsonb_typeof(v_m) <> 'object' or length(btrim(coalesce(v_m ->> 'material', ''))) not between 2 and 80 then perform tecnica.f_error('Cada material lleva su nombre (2 a 80 caracteres)'); end if;
    if coalesce((v_m ->> 'cantidad')::numeric, 0) <= 0 or (v_m ->> 'cantidad')::numeric >= 1000000 then perform tecnica.f_error(format('La cantidad de «%s» no es válida', btrim(v_m ->> 'material'))); end if;
    if not exists (select 1 from redes.unidades_material where codigo = v_m ->> 'unidad' and activo) then perform tecnica.f_error(format('Elija la unidad de «%s»', btrim(v_m ->> 'material'))); end if;
  end loop;

  -- 5. quién la ejecuta
  if coalesce(d ->> 'ejecutor', '') not in ('emdupar', 'contratista') then perform tecnica.f_error('Diga quién la ejecuta: EMDUPAR o contratista'); end if;
  if d ->> 'ejecutor' = 'contratista' then
    if nullif(d ->> 'contratista', '') is not null then
      select id into v_ctr from redes.contratistas where codigo = d ->> 'contratista' and activo;
      if v_ctr is null then perform tecnica.f_error('Ese contratista no está en el catálogo'); end if;
    else
      v_ctr_nom := nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '');
      if v_ctr_nom is null or length(v_ctr_nom) not between 2 and 120 then perform tecnica.f_error('Elija o escriba el contratista'); end if;
    end if;
  elsif nullif(d ->> 'contratista', '') is not null or nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '') is not null then
    perform tecnica.f_error('El contratista solo va si la ejecuta un contratista');
  end if;
  if v_orden is not null and length(v_orden) > 60 then perform tecnica.f_error('El contrato u orden admite hasta 60 caracteres'); end if;
  if v_comp is not null and length(v_comp) not between 2 and 200 then perform tecnica.f_error('Los compañeros de cuadrilla admiten hasta 200 caracteres'); end if;

  -- 6. de dónde salen los recursos (D-8): el operario marca solo quién aporta; el supervisor y el administrador pueden poner valores
  v_fuentes := redes.f_fuentes_validas(d -> 'fuentes', v_super, false);

  -- 7. fotos (JPEG) y documentos (PDF): el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_arch) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_arch);
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_arch) e) then
    perform tecnica.f_error('El orden de los archivos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  for v_f in select e from jsonb_array_elements(v_arch) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'clase', '') not in ('antes', 'durante', 'despues', 'documento') then perform tecnica.f_error('Cada foto dice si es de antes, de durante o de después'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^intervenciones/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || case when v_f ->> 'clase' = 'documento' then '\.pdf$' else '\.jpg$' end) then
      perform tecnica.f_error(format('La ruta del archivo %s no corresponde a esta intervención', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró el archivo %s: súbalo de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('El archivo %s está vacío', v_f ->> 'n')); end if;
    if v_f ->> 'clase' = 'documento' then
      v_nd := v_nd + 1;
      if v_mime is distinct from 'application/pdf' then perform tecnica.f_error(format('El documento %s debe ser PDF', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_doc_itv') then perform tecnica.f_error(format('El documento %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_doc_itv') / 1024)::integer)); end if;
    else
      v_nf := v_nf + 1;
      if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_foto_itv') then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_foto_itv') / 1024)::integer)); end if;
    end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'clase', v_f ->> 'clase', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;
  if v_nf > v_prep.fotos or v_nd > v_prep.documentos or v_nf > redes.f_param('max_fotos_itv') or v_nd > redes.f_param('max_docs_itv') then
    perform tecnica.f_error(format('Una intervención lleva hasta %s fotos y %s documentos', redes.f_param('max_fotos_itv')::integer, redes.f_param('max_docs_itv')::integer));
  end if;
  -- en la calle, siempre al menos una foto; sin fotos solo el supervisor o el administrador (p. ej., desde el escritorio), con el motivo
  if v_nf = 0 then
    if not v_super then perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer)); end if;
    if v_sinev is null or length(v_sinev) not between 10 and 300 then
      perform tecnica.f_error('Sin fotos, escriba por qué no hay evidencia fotográfica (10 a 300 caracteres)');
    end if;
  elsif v_nf < redes.f_param('min_fotos_itv') and not v_super then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  elsif v_sinev is not null then
    perform tecnica.f_error('Con fotos, no marque «sin evidencia fotográfica»');
  end if;

  -- código ITV-000123 (candado de fila del consecutivo)
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'ITV' returning ultimo into v_cons;
  v_codigo := 'ITV-' || lpad(v_cons::text, 6, '0');

  -- inversión, activo nuevo: el activo nace con la intervención, «por verificar», con su origen según quién aporta
  if v_modo = 'nuevo' then
    select case when bool_and(f ->> 'aportante' = 'emdupar') then 'emdupar' when bool_or(f ->> 'aportante' = 'emdupar') then 'mixto' else 'tercero' end,
           (select f2 ->> 'aportante' from jsonb_array_elements(v_fuentes) f2 where f2 ->> 'aportante' <> 'emdupar' order by (f2 ->> 'n')::integer limit 1)
      into v_origen, v_aport from jsonb_array_elements(v_fuentes) f;
    v_activo := redes.f_activo_crear(v_tn.prefijo, v_geom_nuevo, v_clase_n, v_mat_n, v_diam_n, v_nom_n, (v_t_fin at time zone 'America/Bogota')::date,
                                     jsonb_build_object('intervencion', v_codigo), v_origen, v_aport, v_email,
                                     format('Creado por la intervención %s (inversión, activo nuevo): por verificar', v_codigo));
    v_creado := true;
    v_cod_nuevo := (select codigo from redes.activos where id = v_activo);
  end if;

  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, inversion_modo, sistema, activo_id, activo_creado, no_ident_que_es, lat, lon,
         ubicacion_origen, precision_m, fuera_de_zona, t_inicio, t_fin, inicio_en, inicio_origen, descripcion, ejecutor, contratista_id, contratista_nombre,
         contrato_orden, companeros, sin_evidencia_motivo, resuelve_dano, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'nace_de', v_dano.id, v_tipo.codigo, v_modo, v_sis, v_activo, v_creado, v_noid, round(v_lat, 6), round(v_lon, 6),
          d ->> 'ubicacion_origen', (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_fin, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          v_desc, d ->> 'ejecutor', v_ctr, v_ctr_nom, v_orden, v_comp, v_sinev, v_resuelve, v_email, v_ahora);
  insert into redes.intervencion_activos (intervencion_id, activo_id, n) select p_id, x, o from unnest(v_tambien) with ordinality u(x, o);
  insert into redes.intervencion_materiales (intervencion_id, n, material, cantidad, unidad)
  select p_id, o, btrim(e ->> 'material'), (e ->> 'cantidad')::numeric, e ->> 'unidad' from jsonb_array_elements(v_mats) with ordinality x(e, o);
  insert into redes.intervencion_fuentes (intervencion_id, version, n, aportante_codigo, entidad, valor, porcentaje, soporte, fuente, autor)
  select p_id, 1, (f ->> 'n')::smallint, f ->> 'aportante', f ->> 'entidad', (f ->> 'valor')::numeric, (f ->> 'porcentaje')::numeric, f ->> 'soporte',
         case when v_super then 'supervisor' else 'formulario' end, v_email from jsonb_array_elements(v_fuentes) f;
  insert into redes.intervencion_archivos (intervencion_id, n, clase, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'clase', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  insert into redes.intervencion_eventos (intervencion_id, tipo, autor) values (p_id, 'cerrada', v_email);       -- flujo A (D-6)
  if v_creado then
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (p_id, 'crear_activo', v_activo, format('Inversión: se creó el activo %s, por verificar', v_cod_nuevo), v_email);
  end if;

  -- intervención que nace de un daño (un daño puede tener varias, David, respuesta 2 al 3a):
  --   · la primera le pone el inicio de la reparación (si no lo tenía) y el daño queda «en atención»;
  --   · la que marca «Con esta queda resuelto el daño» le pone el servicio restablecido y lo deja «atendido».
  if v_dano.id is not null then
    if v_dano.t_inicio_reparacion is null or v_resuelve then
      insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor)
      values (v_dano.id, case when v_dano.t_inicio_reparacion is null then v_t_ini end, case when v_resuelve then v_t_fin end, 'intervencion', v_email);
    end if;
    insert into redes.dano_eventos (dano_id, tipo, intervencion_id, motivo, autor)
    values (v_dano.id, case when v_resuelve then 'atendido' else 'en_atencion' end, p_id,
            case when v_resuelve then format('Resuelto con la intervención %s (%s)', v_codigo, v_tipo.nombre)
                 else format('Atendido en parte con la intervención %s (%s); sigue abierto', v_codigo, v_tipo.nombre) end, v_email);
    select x.estado into v_dano_estado from redes.v_dano x where x.id = v_dano.id;
  end if;

  -- auditoría sin la posición ni los valores
  perform tecnica.f_auditar(v_email, 'redes_crear_intervencion', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'nace_de', d ->> 'nace_de', 'dano', v_dano.codigo,
          'sistema', v_sis, 'activo', coalesce(v_act.codigo, v_cod_nuevo), 'activo_creado', v_creado, 'no_identificado', v_noid is not null, 'tambien', cardinality(v_tambien),
          'fotos', v_nf, 'documentos', v_nd, 'sin_evidencia', v_nf = 0, 'ejecutor', d ->> 'ejecutor', 'resuelve_dano', v_resuelve), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo, 'activo_creado', x.activo_creado,
                                    'dano', x.dano_codigo, 'dano_estado', v_dano_estado, 'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fuera_de_zona', x.fuera_de_zona,
                                    'duracion_s', x.duracion_s, 'repetido', false) from redes.v_intervencion x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.intervenciones where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_intervencion x where x.id = p_id);
  end if;
  perform tecnica.f_error('Uno de los archivos ya está usado en otra intervención');
  return null;
end $f$;

-- ---------- Supervisor: recursos (D-8). Versión nueva de las fuentes con el valor o el porcentaje y el soporte. ----------
create function public.geoportal_redes_intervencion_recursos(p_solicitante text, p_ref text, p_fuentes jsonb, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'completa los recursos'); i redes.v_intervencion%rowtype; v_f jsonb; v_ver integer; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform pg_advisory_xact_lock(hashtext('redes.itv.' || upper(btrim(coalesce(p_ref, '')))));
  select * into i from redes.v_intervencion where codigo = upper(btrim(coalesce(p_ref, '')));
  if not found then perform tecnica.f_error('No existe esa intervención', 'P0002'); end if;
  if i.estado = 'oculta' then perform tecnica.f_error('Esa intervención está oculta'); end if;
  v_f := redes.f_fuentes_validas(p_fuentes, true, true);
  if v_mot is not null and length(v_mot) not between 10 and 1000 then perform tecnica.f_error('El motivo lleva de 10 a 1.000 caracteres'); end if;
  if i.recursos = 'completos' and v_mot is null then perform tecnica.f_error('Los recursos ya estaban completos: para cambiarlos, escriba el motivo'); end if;
  v_ver := (select max(version) from redes.intervencion_fuentes where intervencion_id = i.id) + 1;
  insert into redes.intervencion_fuentes (intervencion_id, version, n, aportante_codigo, entidad, valor, porcentaje, soporte, fuente, autor)
  select i.id, v_ver, (f ->> 'n')::smallint, f ->> 'aportante', f ->> 'entidad', (f ->> 'valor')::numeric, (f ->> 'porcentaje')::numeric, f ->> 'soporte', 'supervisor', v_email
    from jsonb_array_elements(v_f) f;
  insert into redes.intervencion_eventos (intervencion_id, tipo, motivo, autor) values (i.id, 'completar_recursos', coalesce(v_mot, 'Recursos completados por el supervisor (versión ' || v_ver || ')'), v_email);
  perform tecnica.f_auditar(v_email, 'redes_intervencion_recursos', i.codigo, jsonb_build_object('version', v_ver, 'fuentes', jsonb_array_length(v_f)), null);
  return jsonb_build_object('codigo', i.codigo, 'version', v_ver, 'recursos', (select recursos from redes.v_intervencion where id = i.id));
end $f$;

-- ---------- Supervisor: lista de intervenciones (recientes, o con recursos por completar), con sus fuentes vigentes ----------
create function public.geoportal_redes_intervenciones(p_solicitante text, p_filtro text default 'recientes', p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la lista de intervenciones'); v_lim integer := coalesce(p_limite, 50);
begin
  if coalesce(p_filtro, '') not in ('recientes', 'recursos_por_completar') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 100 then perform tecnica.f_error('Se piden de 1 a 100 intervenciones'); end if;
  return jsonb_build_object('filtro', p_filtro, 'intervenciones', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'tipo', x.tipo_nombre, 'inversion_modo', x.inversion_modo, 'sistema', x.sistema, 'activo', x.activo_codigo,
             'no_identificado', x.no_ident_que_es, 'dano', x.dano_codigo, 't_fin', x.t_fin, 'ejecutor', x.ejecutor, 'contratista', x.contratista, 'autor', x.autor,
             'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fotos', x.fotos, 'estado', x.estado,
             'fuentes', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('n', f.n, 'aportante', f.aportante_codigo, 'aportante_nombre', e.nombre, 'entidad', f.entidad, 'valor', f.valor,
                                                                               'porcentaje', f.porcentaje, 'soporte', f.soporte)) order by f.n)
                           from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo where f.intervencion_id = x.id))
             order by x.registrado_en desc)
      from (select * from redes.v_intervencion v
             where v.estado <> 'oculta' and (p_filtro = 'recientes' or v.recursos = 'por_completar')
             order by v.registrado_en desc limit v_lim) x), '[]'::jsonb));
end $f$;

-- ---------- Supervisor: bandeja de «activo no identificado» con la propuesta de los activos más cercanos ----------
create function public.geoportal_redes_no_identificados(p_solicitante text, p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la bandeja de no identificados'); v_lim integer := coalesce(p_limite, 50); v_radio numeric := redes.f_param('itv_radio_propuesta_m');
begin
  if v_lim < 1 or v_lim > 100 then perform tecnica.f_error('Se piden de 1 a 100'); end if;
  return jsonb_build_object('radio_m', v_radio, 'pendientes', (select count(*) from redes.v_no_identificados), 'items', coalesce((
    select jsonb_agg(jsonb_build_object('clase', n.clase, 'codigo', n.codigo, 'sistema', n.sistema, 'que_es', n.que_es, 'resumen', n.resumen, 'estado', n.estado,
             'cuando', n.cuando, 'autor', n.autor, 'lat', n.lat, 'lon', n.lon,
             -- a igual distancia (al decímetro), primero los puntos (pozo, válvula…) y después los tramos que llegan a ellos, como en «cerca de mí»
             'propuestos', coalesce((select jsonb_agg(redes.f_activo_corto(c.activo_id) || jsonb_build_object('distancia_m', c.dist) order by c.dist, c.es_linea, c.codigo)
                                      from (select m.activo_id, m.codigo, round(ST_Distance(m.geom::geography, n.geom::geography)::numeric, 1) as dist, GeometryType(m.geom) <> 'POINT' as es_linea
                                              from redes.activo_vigente_mat m
                                             where m.sistema = n.sistema and not m.retirado and not m.oculto and ST_DWithin(m.geom::geography, n.geom::geography, v_radio)
                                             order by m.geom <-> n.geom limit 3) c), '[]'::jsonb))
             order by n.registrado_en desc)
      from (select * from redes.v_no_identificados order by registrado_en desc limit v_lim) n), '[]'::jsonb));
end $f$;

-- ---------- Supervisor: asociar un activo a una intervención o a un daño «no identificado» (evento; no se reescribe nada) ----------
create function public.geoportal_redes_asociar_activo(p_solicitante text, p_clase text, p_ref text, p_activo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'asocian activos'); v_id uuid; v_sis text; v_actual bigint; a redes.activo_vigente_mat%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_clase, '') not in ('intervencion', 'dano') then perform tecnica.f_error('Diga si es una intervención o un daño'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.asociar.' || upper(btrim(coalesce(p_ref, '')))));
  if p_clase = 'intervencion' then
    select id, sistema, activo_id into v_id, v_sis, v_actual from redes.v_intervencion where codigo = upper(btrim(coalesce(p_ref, ''))) and estado <> 'oculta';
  else
    select id, sistema, activo_id into v_id, v_sis, v_actual from redes.v_dano where codigo = upper(btrim(coalesce(p_ref, ''))) and estado <> 'oculto';
  end if;
  if v_id is null then perform tecnica.f_error('No existe ese registro (o está oculto)', 'P0002'); end if;
  if v_actual is not null then perform tecnica.f_error('Ese registro ya tiene activo'); end if;
  select * into a from redes.activo_vigente_mat where activo_id = redes.f_buscar_activo(p_activo);
  if a.retirado then perform tecnica.f_error('Ese activo está retirado'); end if;
  if a.sistema <> v_sis then perform tecnica.f_error('Ese activo no es del mismo sistema'); end if;
  if p_clase = 'intervencion' then
    if exists (select 1 from redes.intervencion_activos where intervencion_id = v_id and activo_id = a.activo_id) then perform tecnica.f_error('Ese activo ya está entre los también intervenidos'); end if;
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', a.activo_id, v_mot, v_email);
  else
    insert into redes.dano_eventos (dano_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', a.activo_id, v_mot, v_email);
  end if;
  perform tecnica.f_auditar(v_email, 'redes_asociar_activo', upper(btrim(p_ref)), jsonb_build_object('clase', p_clase, 'activo', a.codigo), null);
  return jsonb_build_object('clase', p_clase, 'codigo', upper(btrim(p_ref)), 'activo', a.codigo);
end $f$;

-- ---------- Daño o falla (Corte 2), con la respuesta 2 de David: sin fotos solo el supervisor o el administrador, con el motivo ----------
create or replace function public.geoportal_redes_preparar_dano(p_solicitante text, p_fotos integer)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_max integer := redes.f_param('max_fotos_dano')::integer; v_min integer;
begin
  v_min := case when tecnica.f_perfil(v_email) in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_dano')::integer end;
  if p_fotos is null or p_fotos < v_min or p_fotos > v_max then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', v_min, v_max));
  end if;
  insert into redes.dano_preparaciones (dano_id, autor, fotos) values (v_id, v_email, p_fotos);
  return jsonb_build_object('dano_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'danos/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n), '[]'::jsonb));
end $f$;

create or replace function public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
  v_super boolean := tecnica.f_perfil(v_email) in ('admin', 'supervisor'); v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'sin_evidencia', not exists (select 1 from redes.dano_fotos f where f.dano_id = p_id), 'repetido', true);
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

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular). Sin fotos: solo supervisor o administrador, con el motivo.
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n = 0 and v_super then
    if v_sinev is null or length(v_sinev) not between 10 and 300 then
      perform tecnica.f_error('Sin fotos, escriba por qué no hay evidencia fotográfica (10 a 300 caracteres), por ejemplo «llegó por la línea 116»');
    end if;
  elsif v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
  elsif v_sinev is not null then
    perform tecnica.f_error('Con fotos, no marque «sin evidencia fotográfica»');
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
  -- «sin evidencia fotográfica»: queda como nota del daño, con el motivo
  if v_n = 0 then insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (p_id, 'nota', 'Sin evidencia fotográfica: ' || v_sinev, v_email); end if;
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'sin_evidencia', v_n = 0, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'sin_evidencia', v_n = 0, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 30 — SEMILLA: los cinco tipos de intervención (maqueta Intervencion.dc.html), unidades de los materiales y parámetros
-- =====================================================================
insert into redes.tipos_intervencion (codigo, nombre, admite_dano, es_inversion, orden) values
  ('preventivo', 'Mantenimiento preventivo', false, false, 1),
  ('correctivo', 'Mantenimiento correctivo', true, false, 2),
  ('reparacion', 'Reparación', true, false, 3),
  ('reposicion', 'Reposición', true, false, 4),
  ('inversion', 'Inversión', false, true, 5);
insert into redes.unidades_material (codigo, nombre, orden) values
  ('und', 'unidad', 1), ('m', 'metro', 2), ('m2', 'm²', 3), ('m3', 'm³', 4), ('kg', 'kg', 5), ('l', 'litro', 6), ('bolsa', 'bolsa', 7), ('global', 'global', 9);
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('itv_dias_atras_max', 7, 'días', 1, 60, 'Cuánto atrás puede empezar una intervención que se registra después de hecha (flujo A)'),
  ('itv_max_horas', 72, 'horas', 1, 720, 'Duración máxima de una intervención (de su inicio a su fin); si duró más, se registra por partes'),
  ('min_fotos_itv', 1, 'fotos', 1, 10, 'Fotos mínimas de una intervención registrada en la calle (el supervisor o el administrador pueden registrar sin fotos, con motivo)'),
  ('max_fotos_itv', 9, 'fotos', 1, 20, 'Fotos máximas de una intervención (antes, durante y después)'),
  ('max_docs_itv', 3, 'documentos', 0, 10, 'Documentos PDF máximos de una intervención (orden, acta, factura)'),
  ('max_bytes_foto_itv', 1572864, 'bytes', 102400, 2097152, 'Tope fino de cada foto de la intervención (1,5 MB)'),
  ('max_bytes_doc_itv', 5242880, 'bytes', 102400, 5242880, 'Tope de cada documento PDF de la intervención (5 MB, el tope del bucket)'),
  ('itv_radio_danos_m', 150, 'm', 10, 1000, 'Radio para proponer los daños abiertos cercanos que atiende una intervención'),
  ('itv_radio_propuesta_m', 50, 'm', 5, 500, 'Radio para proponer los activos más cercanos a un registro «no identificado» (bandeja del supervisor)'),
  ('itv_max_activos_tambien', 10, 'activos', 1, 30, 'Activos también intervenidos, como máximo, además del principal'),
  ('itv_max_materiales', 20, 'materiales', 1, 50, 'Materiales por intervención, como máximo')
on conflict (clave) do nothing;   -- si una reversa anterior los conservó (redes.parametros no deja borrar filas), se reutilizan con su valor
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas de redes: RLS activa sin políticas y ningún privilegio para la API. Funciones internas: nadie de la API.
-- RPC public.geoportal_redes_* nuevas: solo execute a service_role. Las dos que se reemplazan (preparar_dano y crear_dano) conservan su ACL
-- (create or replace no la cambia) y aquí se vuelve a dejar igual, por si acaso.
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
           ('geoportal_redes_formulario_intervencion', 'geoportal_redes_danos_abiertos', 'geoportal_redes_preparar_intervencion', 'geoportal_redes_crear_intervencion',
            'geoportal_redes_intervencion_recursos', 'geoportal_redes_intervenciones', 'geoportal_redes_no_identificados', 'geoportal_redes_asociar_activo',
            'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 30 y 40, en la misma transacción.
-- Se corre DESPUÉS de la carga real del 1a y del Corte 2 publicados: NO supone códigos (RED-000001 es un tubo real; DAN-… e ITV-… pueden
-- existir), ni conteos de la base, ni que no haya daños reales cerca. Toma sus códigos de lo que crea (por la llave de su red de prueba,
-- ID 99300xx y LABEL ZT3-…) y compara siempre contra lo suyo. Al publicar su red, lo real de esas capas queda «retirado» dentro de la
-- transacción, que se deshace al final.
-- No deja rastro: crea sus usuarios (prueba.redes3.*), su red, sus daños, sus archivos de prueba en storage.objects y termina con un ERROR
-- a propósito que deshace todo y trae el informe en el mensaje.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 3a … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
create function pg_temp.sha(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;
-- posición de prueba: x, y en metros aproximados desde un origen dentro de Valledupar
create function pg_temp.p(x numeric, y numeric) returns text language sql as $$ select (-73.2400 + x * 0.0000091)::text || ' ' || (10.4700 + y * 0.0000090)::text $$;
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4700 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.2400 + x * 0.0000091, 6) $$;
create function pg_temp.tramo(p_orden integer, p_id integer, p_label text, p_ini text, p_ini_nom text, p_fin text, p_fin_nom text, p_wkt text) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', p_wkt, 'atributos', jsonb_build_object('ID', p_id, 'LABEL', p_label, 'MATERIAL', 'PVC', 'D', 3, 'LENGTH', 100, 'ZONE', null,
         'IS_ACTIVE?', true, 'CHK_VLVE?', false, 'STARTNODID', p_ini, 'STARTNODE', p_ini_nom, 'STOPNODEID', p_fin, 'STOPNODE', p_fin_nom)) $$;
-- archivo de prueba en Storage (la subida real la hace el celular con la URL firmada)
create function pg_temp.archivo(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- datos base de una intervención válida (se cambian claves en cada prueba)
create function pg_temp.itv(p_archivos jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(50), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-1 hours'),
         'descripcion', 'Revisión y limpieza de prueba del tramo', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar',
         'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')), 'archivos', p_archivos) || p_extra $$;
create function pg_temp.a1(p_ruta text, p_clase text default 'despues') returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('n', 1, 'clase', p_clase, 'ruta', p_ruta)) $$;
-- un daño válido (para los que se atienden), con su foto ya en Storage
create function pg_temp.dano(p_quien text, p_extra jsonb) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_quien, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_quien, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(40), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-5 hours'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_extra);
end $$;
-- prepara una intervención y sube sus archivos de prueba; devuelve la preparación
create function pg_temp.preparar(p_quien text, p_fotos integer, p_docs integer default 0) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_intervencion(p_quien, p_fotos, p_docs); x jsonb;
begin
  for x in select e from jsonb_array_elements(v_p -> 'fotos') e loop perform pg_temp.archivo(x ->> 'ruta'); end loop;
  for x in select e from jsonb_array_elements(v_p -> 'documentos') e loop perform pg_temp.archivo(x ->> 'ruta', 800000, 'application/pdf'); end loop;
  return v_p;
end $$;

do $prueba$
declare
  a text := 'prueba.redes3.adm@emdupar.gov.co'; sv text := 'prueba.redes3.sup@emdupar.gov.co'; op text := 'prueba.redes3.op@emdupar.gov.co';
  sf text := 'prueba.redes3.sinform@emdupar.gov.co'; na text := 'prueba.redes3.nada@emdupar.gov.co';
  v_red1 text; v_red2 text; v_val text; v_acc text; v_tor text; v_poz1 text; v_poz2 text; v_col text;
  v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_id uuid; v_ruta text;
  v_d1 text; v_d2 text; v_d3 text; v_d4 text; v_d5 text; v_dn text; v_itv0 bigint; v_tes0 integer;
  v_ia text; v_ib text; v_ic text; v_id_txt text; v_ie text; v_if text; v_ig text; v_nuevo_red text; v_nuevo_val text; v_ida uuid;
  v_total integer; v_bien integer; v_fallas text;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'Supervisor', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (sf, 'Operador sin el formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'mantenimiento', a), (op, 'asignar_formulario', 'danos_fallas', a),
    (sf, 'asignar_formulario', 'danos_fallas', a);

  -- red de prueba con el motor del 1a: 2 tramos de acueducto (V993 → Tee-993 → Torre-993) y 2 pozos con un conducto
  v_c := (public.geoportal_redes_carga_iniciar(a, 'acueducto', pg_temp.sha('zt3-acu'), 'shp', 4326, 'ID', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.tramo(1, 9930001, 'Distribucion-ZT31', '99301', 'V993', '99302', 'Tee-993', w1), pg_temp.tramo(2, 9930002, 'Lateral-ZT32', '99302', 'Tee-993', '99303', 'Torre-993', w2)));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Red de prueba del Corte 3a');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_pozos', pg_temp.sha('zt3-poz'), 'shp', 4326, 'LABEL', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', 'POINT(' || pg_temp.p(0, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT3-PA', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 98)),
    jsonb_build_object('orden', 2, 'wkt', 'POINT(' || pg_temp.p(100, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT3-PB', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 97))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Pozos de prueba del Corte 3a');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_conductos', pg_temp.sha('zt3-con'), 'shp', 4326, 'LABEL', 1) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(jsonb_build_object('orden', 1, 'wkt', 'LINESTRING(' || pg_temp.p(0, 300) || ',' || pg_temp.p(100, 300) || ')',
    'atributos', jsonb_build_object('LABEL', 'ZT3-PA-PB', 'PZ_INICIAL', 'ZT3-PA', 'PZ_FINAL', 'ZT3-PB', 'MATERIAL', 'PVC', 'DIAMETRO', 200, 'ESTADO', 'Existente'))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Conducto de prueba del Corte 3a');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9930001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9930002';
  select codigo into v_val from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99301';
  select codigo into v_acc from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99302';
  select codigo into v_tor from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99303';
  select codigo into v_poz1 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT3-PA';
  select codigo into v_poz2 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT3-PB';
  select codigo into v_col from redes.v_activo_vigente where capa_codigo = 'alc_conductos' and llave_capa = 'ZT3-PA-PB';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED, VAL, ACC, TOR, 2 POZ y COL, encontrados por su llave',
     v_red1 like 'RED-%' and v_red2 like 'RED-%' and v_val like 'VAL-%' and v_acc like 'ACC-%' and v_tor like 'TOR-%' and v_poz1 like 'POZ-%' and v_poz2 like 'POZ-%' and v_col like 'COL-%'
     and (select count(*) from redes.activo_vigente_mat where codigo in (v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col) and not retirado) = 8,
     concat_ws(' ', v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col));
  select ultimo into v_itv0 from redes.consecutivos where prefijo = 'ITV';
  select version into v_tes0 from redes.tesela_version where sistema = 'acueducto';

  -- ---------- 01 Catálogo, parámetros y reglas ----------
  perform pg_temp.reg('01.01 cinco tipos (correctivo, reparación y reposición atienden daños; inversión aparte) y 8 unidades',
     (select string_agg(codigo, ',' order by orden) from redes.tipos_intervencion) = 'preventivo,correctivo,reparacion,reposicion,inversion'
     and (select string_agg(codigo, ',' order by orden) from redes.tipos_intervencion where admite_dano) = 'correctivo,reparacion,reposicion'
     and (select es_inversion from redes.tipos_intervencion where codigo = 'inversion') and (select count(*) from redes.unidades_material) = 8);
  perform pg_temp.reg('01.02 parámetros: 7 días atrás, 72 h, 1 a 9 fotos, 3 PDF, 150 m para los daños, 50 m para la propuesta',
     redes.f_param('itv_dias_atras_max') = 7 and redes.f_param('itv_max_horas') = 72 and redes.f_param('min_fotos_itv') = 1 and redes.f_param('max_fotos_itv') = 9
     and redes.f_param('max_docs_itv') = 3 and redes.f_param('itv_radio_danos_m') = 150 and redes.f_param('itv_radio_propuesta_m') = 50);
  perform pg_temp.err('01.03 un tipo de intervención no se borra', $$delete from redes.tipos_intervencion where codigo = 'preventivo'$$, '42501');
  perform pg_temp.err('01.04 el código de un tipo no cambia', $$update redes.tipos_intervencion set codigo = 'prev' where codigo = 'preventivo'$$, '42501');

  -- ---------- 02 Permisos ----------
  perform pg_temp.reg('02.01 ningún privilegio de la API sobre las tablas y vistas; RLS activa en todas',
     not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                  where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S') and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert')))
     and not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity));
  perform pg_temp.reg('02.02 las 8 RPC nuevas y las 2 reemplazadas: security definer, search_path fijo y solo service_role', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
       ('geoportal_redes_formulario_intervencion', 'geoportal_redes_danos_abiertos', 'geoportal_redes_preparar_intervencion', 'geoportal_redes_crear_intervencion',
        'geoportal_redes_intervencion_recursos', 'geoportal_redes_intervenciones', 'geoportal_redes_no_identificados', 'geoportal_redes_asociar_activo',
        'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano')
       and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 10);
  perform pg_temp.reg('02.03 las funciones internas (crear activo, fuentes, supervisor…) no las ejecuta la API',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_activo_crear', 'f_mat_refrescar_uno', 'f_fuentes_validas', 'f_supervisor', 'f_dano_elegible')
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))));

  -- ---------- 03 Formulario ----------
  v_r := public.geoportal_redes_formulario_intervencion(op);
  perform pg_temp.reg('03.01 operador con «mantenimiento»: 5 tipos, aportantes, unidades, tipos de activo nuevo; al menos 1 foto y sin valores',
     v_r ->> 'perfil' = 'operador' and jsonb_array_length(v_r -> 'tipos') = 5 and jsonb_array_length(v_r -> 'unidades') = 8
     and exists (select 1 from jsonb_array_elements(v_r -> 'aportantes') x where x ->> 'codigo' = 'alcaldia')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tipos_nuevo') x where x ->> 'prefijo' = 'RED' and x ->> 'geometria' = 'linea')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tipos_nuevo') x where x ->> 'prefijo' = 'VAL' and (x ->> 'clase_obligatoria')::boolean)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'tipos_nuevo') x where x ->> 'prefijo' in ('SEC', 'SEN', 'SCA'))
     and (v_r -> 'reglas' ->> 'min_fotos')::integer = 1 and not (v_r -> 'reglas' ->> 'puede_sin_fotos')::boolean and not (v_r -> 'reglas' ->> 'pone_valores')::boolean, left(v_r::text, 400));
  perform pg_temp.err('03.02 operador SIN «mantenimiento»: 42501', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, sf), '42501');
  perform pg_temp.err('03.03 sin Técnica: 42501', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, na), '42501');
  v_r := public.geoportal_redes_formulario_intervencion(sv);
  perform pg_temp.reg('03.04 el supervisor pasa sin asignación; puede registrar sin fotos y poner los valores',
     v_r ->> 'perfil' = 'supervisor' and (v_r -> 'reglas' ->> 'min_fotos')::integer = 0 and (v_r -> 'reglas' ->> 'puede_sin_fotos')::boolean and (v_r -> 'reglas' ->> 'pone_valores')::boolean);

  -- ---------- 04 Preparar ----------
  perform pg_temp.err('04.01 el operador no prepara sin fotos', format($$select public.geoportal_redes_preparar_intervencion(%L, 0)$$, op), '22023', 'de 1 a 9 fotos');
  perform pg_temp.err('04.02 diez fotos', format($$select public.geoportal_redes_preparar_intervencion(%L, 10)$$, op), '22023');
  perform pg_temp.err('04.03 cuatro documentos', format($$select public.geoportal_redes_preparar_intervencion(%L, 1, 4)$$, op), '22023', 'documentos');
  v_p := pg_temp.preparar(op, 2, 1);
  v_id := (v_p ->> 'intervencion_id')::uuid; v_ruta := v_p -> 'fotos' -> 0 ->> 'ruta';
  perform pg_temp.reg('04.04 preparar 2 fotos y 1 documento: id reservado; rutas 1.jpg, 2.jpg y 3.pdf bajo intervenciones/AAAA-MM/<id>/',
     jsonb_array_length(v_p -> 'fotos') = 2 and v_ruta ~ ('^intervenciones/[0-9]{4}-[0-9]{2}/' || v_id || '/1\.jpg$')
     and v_p -> 'documentos' -> 0 ->> 'ruta' ~ ('/' || v_id || '/3\.pdf$') and exists (select 1 from redes.intervencion_preparaciones where intervencion_id = v_id and autor = op), v_p::text);
  perform pg_temp.reg('04.05 el supervisor sí prepara sin fotos', jsonb_array_length(public.geoportal_redes_preparar_intervencion(sv, 0) -> 'fotos') = 0);

  -- ---------- 05 Daños de prueba y «daños abiertos» cercanos ----------
  v_d1 := pg_temp.dano(op, '{}') ->> 'codigo';                                                                          -- en el tramo 1, reportado
  v_d2 := pg_temp.dano(op, jsonb_build_object('activo', v_red2, 'lon', pg_temp.lon(150), 't_inicio_reparacion', pg_temp.iso('-4 hours'))) ->> 'codigo';   -- tramo 2, en atención
  v_d3 := pg_temp.dano(op, jsonb_build_object('t_inicio_reparacion', pg_temp.iso('-4 hours'), 't_restablecido', pg_temp.iso('-3 hours'))) ->> 'codigo';  -- atendido
  v_d4 := pg_temp.dano(op, jsonb_build_object('sistema', 'alcantarillado', 'tipo', 'rebose', 'tipo_rotura', null, 'activo', v_poz1, 'lat', pg_temp.lat(300), 'lon', pg_temp.lon(0))) ->> 'codigo';
  v_d5 := pg_temp.dano(op, jsonb_build_object('activo', null, 'no_identificado', 'Fuga lejos de la red de prueba', 'lat', pg_temp.lat(2000), 'lon', pg_temp.lon(0), 'ubicacion_origen', 'mapa')) ->> 'codigo';
  perform pg_temp.reg('05.01 cinco daños de prueba creados con el formulario del Corte 2', v_d1 like 'DAN-%' and v_d2 like 'DAN-%' and v_d3 like 'DAN-%' and v_d4 like 'DAN-%' and v_d5 like 'DAN-%'
     and (select estado from redes.v_dano where codigo = v_d2) = 'en_atencion' and (select estado from redes.v_dano where codigo = v_d3) = 'atendido', concat_ws(' ', v_d1, v_d2, v_d3, v_d4, v_d5));
  v_r := public.geoportal_redes_danos_abiertos(op, 'acueducto', v_red1);
  perform pg_temp.reg('05.02 daños abiertos del tramo 1: primero el suyo, luego el del tramo vecino (a ~100 m); no el atendido, ni el de alcantarillado, ni el lejano',
     v_r -> 'danos' -> 0 ->> 'codigo' = v_d1 and (v_r -> 'danos' -> 0 ->> 'mismo_activo')::boolean
     and exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' = v_d2 and not (x ->> 'mismo_activo')::boolean)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' in (v_d3, v_d4, v_d5)), v_r::text);
  v_r := public.geoportal_redes_danos_abiertos(op, 'alcantarillado', null, pg_temp.lat(300), pg_temp.lon(5));
  perform pg_temp.reg('05.03 por posición (sin activo), en alcantarillado: el rebose del pozo', exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' = v_d4)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' in (v_d1, v_d2)));
  perform pg_temp.reg('05.04 la lista no trae autores, nombres ni placas', position('@' in public.geoportal_redes_danos_abiertos(op, 'acueducto', v_red1)::text) = 0);
  perform pg_temp.err('05.05 daños abiertos sin el formulario: 42501', format($$select public.geoportal_redes_danos_abiertos(%L, 'acueducto', %L)$$, sf, v_red1), '42501');
  perform pg_temp.err('05.06 daños abiertos sin activo ni punto', format($$select public.geoportal_redes_danos_abiertos(%L, 'acueducto')$$, op), '22023', 'activo');

  -- ---------- 06 Crear: validaciones (cada una con el texto para la persona) ----------
  perform pg_temp.err('06.01 sin preparar', format($$select public.geoportal_redes_crear_intervencion(%L, gen_random_uuid(), %L)$$, op, pg_temp.itv(pg_temp.a1(v_ruta))), '22023', 'prepararse');
  perform pg_temp.err('06.02 el id preparado por otra persona', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sv, v_id, pg_temp.itv(pg_temp.a1(v_ruta))), '22023', 'prepararse');
  perform pg_temp.err('06.03 sin «de dónde nace»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"nace_de": null}')), '22023', 'de dónde nace');
  perform pg_temp.err('06.04 tipo que no existe', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"tipo": "pintura"}')), '22023', 'tipo de intervención');
  perform pg_temp.err('06.05 un preventivo no atiende un daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'dano', v_d1))), '22023', 'no atiende un daño');
  perform pg_temp.err('06.06 inversión sin decir si es activo nuevo o mejora', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"tipo": "inversion"}')), '22023', 'activo nuevo o mejora');
  perform pg_temp.err('06.07 sin sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"sistema": "gas"}')), '22023', 'sistema');
  perform pg_temp.err('06.08 activo de otro sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('activo', v_poz1))), '22023', 'no es de ese sistema');
  perform pg_temp.err('06.09 sin activo ni «qué es»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"activo": null}')), '22023', 'diga qué es');
  perform pg_temp.err('06.10 el principal repetido en «también intervenidos»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tambien', jsonb_build_array(v_red1)))), '22023', 'principal');
  perform pg_temp.err('06.11 también intervenido de otro sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tambien', jsonb_build_array(v_col)))), '22023', 'no es de ese sistema');
  perform pg_temp.err('06.12 también intervenido repetido', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tambien', jsonb_build_array(v_val, lower(v_val))))), '22023', 'repetido');
  perform pg_temp.err('06.13 fin en el futuro', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_fin', pg_temp.iso('30 minutes')))), '22023', 'futuro');
  perform pg_temp.err('06.14 inicio después del fin', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_inicio', pg_temp.iso('-1 hours'), 't_fin', pg_temp.iso('-2 hours')))), '22023', 'después del fin');
  perform pg_temp.err('06.15 inicio de hace más de 7 días', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_inicio', pg_temp.iso('-8 days')))), '22023', '7 días');
  perform pg_temp.err('06.16 más de 72 horas', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_inicio', pg_temp.iso('-4 days')))), '22023', '72 horas');
  perform pg_temp.err('06.17 formulario abierto hace más de 12 horas', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('inicio_dispositivo', pg_temp.iso('-13 hours')))), '22023', '12 horas');
  perform pg_temp.err('06.18 hora mal escrita', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"t_fin": "hoy a las 3"}')), '22023', 'forma esperada');
  perform pg_temp.err('06.19 daño que no existe', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"nace_de": "dano", "tipo": "reparacion", "dano": "DAN-ZZZ"}')), '22023', 'no existe');
  perform pg_temp.err('06.20 daño ya atendido', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d3))), '22023', 'ya está atendido');
  perform pg_temp.err('06.21 daño lejano (a ~1,8 km)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d5))), '22023', 'ni de los cercanos');
  perform pg_temp.err('06.22 daño de otro sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d4))), '22023', 'ni de los cercanos');
  perform pg_temp.err('06.23 la intervención empezó antes de que se detectara el daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1, 't_inicio', pg_temp.iso('-6 hours')))), '22023', 'antes de que se detectara');
  perform pg_temp.err('06.24 descripción corta', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"descripcion": "listo"}')), '22023', 'Describa');
  perform pg_temp.err('06.25 material sin unidad', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"materiales": [{"material": "Tubo PVC 3 pulg", "cantidad": 6}]}')), '22023', 'unidad');
  perform pg_temp.err('06.26 material con cantidad 0', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"materiales": [{"material": "Tubo PVC 3 pulg", "cantidad": 0, "unidad": "m"}]}')), '22023', 'cantidad');
  perform pg_temp.err('06.27 ejecuta EMDUPAR pero trae contratista', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"contratista_nombre": "Obras ZT SAS"}')), '22023', 'contratista');
  perform pg_temp.err('06.28 contratista sin nombre', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"ejecutor": "contratista"}')), '22023', 'contratista');
  perform pg_temp.err('06.29 sin fuentes de recursos', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": []}')), '22023', 'quién aporta');
  perform pg_temp.err('06.30 el operario no pone valores (D-8)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": [{"aportante": "emdupar", "valor": 1000000}]}')), '22023', 'los pone el supervisor');
  perform pg_temp.err('06.31 «Otro» sin decir cuál', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": [{"aportante": "otro"}]}')), '22023', 'otra entidad');
  perform pg_temp.err('06.32 fuente repetida', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": [{"aportante": "emdupar"}, {"aportante": "emdupar"}]}')), '22023', 'repetida');
  perform pg_temp.err('06.33 foto que no se subió', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(replace(v_ruta, '/1.jpg', '/9.jpg')))), '22023');
  perform pg_temp.err('06.34 ruta de otra intervención', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1('intervenciones/2026-11/00000000-0000-4000-8000-000000000000/1.jpg'))), '22023', 'no corresponde');
  perform pg_temp.archivo(replace(v_ruta, '/1.jpg', '/1.pdf'), 400000, 'application/pdf');
  perform pg_temp.err('06.35 el operador sin fotos (solo un PDF)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'documento', 'ruta', replace(v_ruta, '/1.jpg', '/1.pdf'))))), '22023', 'al menos 1 foto');
  perform pg_temp.archivo(replace(v_ruta, '/1.jpg', '/2.pdf'));
  perform pg_temp.err('06.36 un documento que no es PDF (el archivo subido es JPEG)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_ruta), jsonb_build_object('n', 2, 'clase', 'documento', 'ruta', replace(v_ruta, '/1.jpg', '/2.pdf'))))), '22023', 'debe ser PDF');
  perform pg_temp.archivo(replace(v_ruta, '/1.jpg', '/3.jpg'), 2000000);
  perform pg_temp.err('06.37 foto de más de 1,5 MB', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'antes', 'ruta', v_ruta), jsonb_build_object('n', 2, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta'),
                                   jsonb_build_object('n', 3, 'clase', 'despues', 'ruta', replace(v_ruta, '/1.jpg', '/3.jpg'))))), '22023');
  perform pg_temp.err('06.38 el operador no marca «sin evidencia»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv('[]'::jsonb, '{"sin_evidencia_motivo": "Llegó por la línea 116"}')), '22023', 'al menos 1 foto');
  perform pg_temp.err('06.39 con fotos y «sin evidencia» a la vez', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"sin_evidencia_motivo": "Llegó por la línea 116"}')), '22023', 'no marque');
  perform pg_temp.err('06.40 activo nuevo de otro sistema (pozo en acueducto)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'POZ', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'tipo del activo nuevo');
  perform pg_temp.err('06.41 válvula nueva sin clase', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'VAL', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'clase');
  perform pg_temp.err('06.42 tramo nuevo con un solo punto', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'RED', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'inicio y el fin');
  perform pg_temp.err('06.43 activo nuevo fuera de Valledupar', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'HID', 'puntos', jsonb_build_array(jsonb_build_array(4.6, -74.08)))))), '22023', 'dentro de Valledupar');
  perform pg_temp.err('06.44 activo nuevo y a la vez un activo existente', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo',
       'nuevo', jsonb_build_object('prefijo', 'HID', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'no lleva un activo existente');
  perform pg_temp.err('06.45 operador sin «mantenimiento» no crea', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sf, v_id, pg_temp.itv(pg_temp.a1(v_ruta))), '42501');
  perform pg_temp.reg('06.46 ninguna validación dejó nada (ni intervención, ni consecutivo, ni daño atendido)', not exists (select 1 from redes.intervenciones)
     and (select ultimo from redes.consecutivos where prefijo = 'ITV') = v_itv0 and (select estado from redes.v_dano where codigo = v_d1) = 'reportado');

  -- ---------- 07 Crear: los buenos ----------
  -- (a) operador: reparación que nace del daño 1, con la válvula también intervenida, materiales, 2 fotos y 1 PDF
  v_r := public.geoportal_redes_crear_intervencion(op, v_id, pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'antes', 'ruta', v_ruta),
            jsonb_build_object('n', 2, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta'), jsonb_build_object('n', 3, 'clase', 'documento', 'ruta', v_p -> 'documentos' -> 0 ->> 'ruta')),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1, 'resuelve_dano', true, 't_inicio', pg_temp.iso('-4 hours'), 't_fin', pg_temp.iso('-2 hours'),
              'inicio_dispositivo', pg_temp.iso('-10 minutes'), 'tambien', jsonb_build_array(v_val), 'companeros', 'Cuadrilla 2',
              'materiales', jsonb_build_array(jsonb_build_object('material', 'Tubo PVC 3 pulg', 'cantidad', 6, 'unidad', 'm'), jsonb_build_object('material', 'Unión de reparación 3 pulg', 'cantidad', 2, 'unidad', 'und')),
              'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')))), '10.0.0.3');
  v_ia := v_r ->> 'codigo';
  perform pg_temp.reg('07.01 se guarda la reparación que marca «queda resuelto»: ITV-…, cerrada, sobre el tramo 1; el daño queda atendido; recursos por completar',
     v_ia ~ '^ITV-[0-9]{6}$' and v_r ->> 'estado' = 'cerrada' and v_r ->> 'activo' = v_red1 and v_r ->> 'dano' = v_d1 and v_r ->> 'dano_estado' = 'atendido'
     and v_r ->> 'recursos' = 'por_completar' and not (v_r ->> 'sin_evidencia')::boolean and not (v_r ->> 'repetido')::boolean
     and (select ultimo from redes.consecutivos where prefijo = 'ITV') = v_itv0 + 1, v_r::text);
  select row_to_json(x)::jsonb into v_x from redes.v_dano x where codigo = v_d1;
  perform pg_temp.reg('07.02 el daño recibe los tiempos de la intervención: reparación de 2 h, respuesta de 1 h y el evento «atendido» con el código',
     (v_x ->> 'reparacion_s')::integer between 7190 and 7210 and (v_x ->> 'respuesta_s')::integer between 3590 and 3610
     and exists (select 1 from redes.dano_eventos e join redes.danos d on d.id = e.dano_id where d.codigo = v_d1 and e.tipo = 'atendido' and e.intervencion_id = v_id and e.motivo like 'Resuelto con la intervención ' || v_ia || '%')
     and exists (select 1 from redes.dano_tiempos t join redes.danos d on d.id = t.dano_id where d.codigo = v_d1 and t.fuente = 'intervencion'), v_x::text);
  perform pg_temp.reg('07.03 quedan los materiales, la válvula también intervenida, la fuente sin valores, 2 fotos y 1 PDF leídos de Storage',
     (select count(*) from redes.intervencion_materiales where intervencion_id = v_id) = 2
     and (select array_agg(a.codigo) from redes.intervencion_activos x join redes.activos a on a.id = x.activo_id where x.intervencion_id = v_id) = array[v_val]
     and (select count(*) from redes.intervencion_fuentes where intervencion_id = v_id and version = 1 and valor is null and porcentaje is null and fuente = 'formulario') = 1
     and (select string_agg(clase || ':' || mime || ':' || bytes, ',' order by n) from redes.intervencion_archivos where intervencion_id = v_id)
         = 'antes:image/jpeg:300000,despues:image/jpeg:300000,documento:application/pdf:800000');
  perform pg_temp.reg('07.04 auditoría con el código y la IP, sin la posición', exists (select 1 from public.geoportal_auditoria where accion = 'redes_crear_intervencion' and referencia = v_ia and ip = '10.0.0.3'
     and detalle ->> 'dano' = v_d1 and not detalle ? 'lat'));
  v_x := public.geoportal_redes_crear_intervencion(op, v_id, pg_temp.itv(pg_temp.a1(v_ruta)));
  perform pg_temp.reg('07.05 reenviar el mismo id devuelve lo guardado («repetido»), sin otro código', v_x ->> 'codigo' = v_ia and (v_x ->> 'repetido')::boolean
     and (select count(*) from redes.intervenciones) = 1);
  v_p := pg_temp.preparar(op, 1);
  perform pg_temp.err('07.06 otra intervención no puede atender el mismo daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, (v_p ->> 'intervencion_id')::uuid,
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1))), '22023', 'ya está atendido');

  -- (b) el daño 2 ya estaba en atención. Un daño puede tener varias intervenciones (David, respuesta 2 al 3a): la primera NO lo resuelve
  --     (sigue en atención, con su inicio de reparación de antes); la segunda marca «queda resuelto» y le pone el restablecido.
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'correctivo', 'dano', v_d2, 'activo', v_red2, 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-150 minutes'))));
  v_ib := v_r ->> 'codigo';
  perform pg_temp.reg('07.07 una intervención que no lo resuelve: el daño sigue «en atención», con un evento que lo dice, sin restablecido',
     v_r ->> 'dano_estado' = 'en_atencion' and (select t_restablecido is null from redes.v_dano where codigo = v_d2)
     and exists (select 1 from redes.dano_eventos e join redes.danos d on d.id = e.dano_id where d.codigo = v_d2 and e.tipo = 'en_atencion' and e.motivo like '%' || v_ib || '%sigue abierto'), v_r::text);
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'reposicion', 'dano', v_d2, 'activo', v_red2, 'resuelve_dano', true, 't_inicio', pg_temp.iso('-2 hours'), 't_fin', pg_temp.iso('-90 minutes'))));
  select row_to_json(x)::jsonb into v_x from redes.v_dano x where codigo = v_d2;
  perform pg_temp.reg('07.07b la segunda marca «queda resuelto»: atendido, con el inicio de reparación de antes (hace 4 h) y el fin de esta (reparación 2,5 h); el daño tiene 2 intervenciones',
     v_r ->> 'dano_estado' = 'atendido' and (v_x ->> 'reparacion_s')::integer between 8990 and 9010
     and (select count(*) from redes.intervenciones i join redes.danos d on d.id = i.dano_id where d.codigo = v_d2) = 2, v_r::text || ' / ' || v_x::text);
  perform pg_temp.err('07.07c «queda resuelto» sin nacer de un daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, (pg_temp.preparar(op, 1) ->> 'intervencion_id')::uuid,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"resuelve_dano": true}')), '22023', 'solo va cuando');

  -- (c) supervisor desde el escritorio: preventivo SIN fotos, con el motivo; contratista escrito; los valores ya puestos
  v_p := public.geoportal_redes_preparar_intervencion(sv, 0); v_ida := (v_p ->> 'intervencion_id')::uuid;
  perform pg_temp.err('07.08 el supervisor sin fotos y sin motivo', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sv, v_ida, pg_temp.itv('[]'::jsonb)), '22023', 'por qué no hay evidencia');
  v_r := public.geoportal_redes_crear_intervencion(sv, v_ida, pg_temp.itv('[]'::jsonb, jsonb_build_object('activo', v_tor, 'sin_evidencia_motivo', 'Lo reportó el contratista por correo; no hay fotos',
            'ejecutor', 'contratista', 'contratista_nombre', 'Obras ZT SAS', 'contrato_orden', 'OT-ZT-77',
            'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar', 'porcentaje', 60, 'soporte', 'Presupuesto 2026'),
                                         jsonb_build_object('aportante', 'gobernacion', 'valor', 4000000, 'soporte', 'Convenio ZT-1')))));
  v_ic := v_r ->> 'codigo'; v_x := v_r;
  v_p := public.geoportal_redes_preparar_intervencion(sv, 0); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_x := public.geoportal_redes_crear_intervencion(sv, v_ida, pg_temp.itv('[]'::jsonb, jsonb_build_object('activo', v_red2, 'sin_evidencia_motivo', 'Obra larga registrada desde el escritorio',
            't_inicio', pg_temp.iso('-20 days'), 't_fin', pg_temp.iso('-10 days'))));
  perform pg_temp.reg('07.08b el supervisor registra una obra larga sin el tope del operario (empezó hace 20 días y duró 10)', v_x ->> 'codigo' ~ '^ITV-' and (v_x ->> 'duracion_s')::integer = 864000, v_x::text);
  perform pg_temp.reg('07.08c el formulario no le pone tope de días ni de horas al supervisor; al operario sí (7 y 72)',
     public.geoportal_redes_formulario_intervencion(sv) -> 'reglas' -> 'dias_atras_max' = 'null'::jsonb and public.geoportal_redes_formulario_intervencion(sv) -> 'reglas' -> 'max_horas' = 'null'::jsonb
     and (public.geoportal_redes_formulario_intervencion(op) -> 'reglas' ->> 'max_horas')::integer = 72);
  v_r := (select jsonb_build_object('sin_evidencia', sin_evidencia, 'recursos', recursos) from redes.v_intervencion where codigo = v_ic);
  perform pg_temp.reg('07.09 se guarda «sin evidencia fotográfica», con el contratista y los recursos completos',
     (v_r ->> 'sin_evidencia')::boolean and v_r ->> 'recursos' = 'completos'
     and exists (select 1 from redes.v_intervencion where codigo = v_ic and contratista = 'Obras ZT SAS' and contrato_orden = 'OT-ZT-77' and sin_evidencia_motivo like 'Lo reportó%'
                  and aportantes = array['EMDUPAR', 'Gobernación del Cesar']), v_r::text);

  -- (d) operador: inversión, tramo nuevo (dos puntos), aporta la alcaldía → activo nuevo «por verificar», origen tercero
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
            'lat', pg_temp.lat(50), 'lon', pg_temp.lon(250), 'ubicacion_origen', 'mapa',
            'nuevo', jsonb_build_object('prefijo', 'RED', 'material', 'PVC', 'diametro_mm', 110, 'nombre', 'Extensión de prueba',
                                        'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(0), pg_temp.lon(200)), jsonb_build_array(pg_temp.lat(100), pg_temp.lon(300)))),
            'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'alcaldia')))));
  v_id_txt := v_r ->> 'codigo'; v_nuevo_red := v_r ->> 'activo';
  perform pg_temp.reg('07.10 inversión en un tramo nuevo: crea RED-… (origen «intervención»), y la intervención queda sobre él',
     v_nuevo_red like 'RED-%' and (v_r ->> 'activo_creado')::boolean and v_nuevo_red not in (v_red1, v_red2)
     and exists (select 1 from redes.activos where codigo = v_nuevo_red and origen_alta = 'intervencion' and creado_por = op), v_r::text);
  perform pg_temp.reg('07.11 el tramo nuevo: «por verificar», en operación, PVC de 110 mm, ~140 m, instalado hoy, en la tabla vigente y con la tesela subida',
     exists (select 1 from redes.v_activo_vigente v where v.codigo = v_nuevo_red and v.por_verificar and v.estado_codigo = 'en_operacion' and v.material_codigo = 'PVC'
              and v.diametro_mm = 110 and v.longitud_m between 130 and 150 and v.fecha_instalacion = (clock_timestamp() at time zone 'America/Bogota')::date and v.atributos ->> 'intervencion' = v_id_txt)
     and exists (select 1 from redes.activo_vigente_mat where codigo = v_nuevo_red and not retirado)
     and (select version from redes.tesela_version where sistema = 'acueducto') > v_tes0);
  perform pg_temp.reg('07.12 el origen del tramo nuevo sale de quién aporta: tercero (alcaldía); solo lo ve el supervisor',
     exists (select 1 from redes.v_activo_origen_vigente o join redes.activos x on x.id = o.activo_id where x.codigo = v_nuevo_red and o.origen = 'tercero' and o.aportante_codigo = 'alcaldia')
     and public.geoportal_redes_activo(op, v_nuevo_red) -> 'origen' is null and public.geoportal_redes_activo(sv, v_nuevo_red) -> 'origen' ->> 'origen' = 'tercero');

  -- (e) operador: inversión, válvula nueva (punto, clase cierre); aportan EMDUPAR y la Nación → origen mixto
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
            'nuevo', jsonb_build_object('prefijo', 'VAL', 'clase', 'cierre', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(0), pg_temp.lon(60)))),
            'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar'), jsonb_build_object('aportante', 'nacion')))));
  v_ie := v_r ->> 'codigo'; v_nuevo_val := v_r ->> 'activo';
  perform pg_temp.reg('07.13 válvula nueva: VAL-… de clase cierre, origen mixto (EMDUPAR y Nación)', v_nuevo_val like 'VAL-%'
     and exists (select 1 from redes.v_activo_vigente where codigo = v_nuevo_val and clase = 'cierre' and GeometryType(geom) = 'POINT' and por_verificar)
     and exists (select 1 from redes.v_activo_origen_vigente o join redes.activos x on x.id = o.activo_id where x.codigo = v_nuevo_val and o.origen = 'mixto' and o.aportante_codigo = 'nacion'), v_r::text);

  -- (f) operador: correctivo en alcantarillado, activo no identificado (marcado en el mapa, al lado del pozo 2)
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'correctivo', 'sistema', 'alcantarillado', 'activo', null,
            'no_identificado', 'Cámara que no sale en el mapa', 'lat', pg_temp.lat(305), 'lon', pg_temp.lon(100), 'ubicacion_origen', 'mapa')));
  v_if := v_r ->> 'codigo';
  perform pg_temp.reg('07.14 «no identificado» en alcantarillado: se guarda sin activo', v_r -> 'activo' = 'null'::jsonb and v_r ->> 'estado' = 'cerrada', v_r::text);

  -- (g) operador: inversión, mejora del pozo 1
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta', 'durante'), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'mejora',
            'sistema', 'alcantarillado', 'activo', v_poz1, 'lat', pg_temp.lat(300), 'lon', pg_temp.lon(0))));
  v_ig := v_r ->> 'codigo';
  perform pg_temp.reg('07.15 inversión de mejora del pozo 1: sin activo nuevo', v_r ->> 'activo' = v_poz1 and not (v_r ->> 'activo_creado')::boolean, v_r::text);

  -- ---------- 08 Epicrisis y ficha ----------
  v_r := public.geoportal_redes_epicrisis(op, v_red1);
  perform pg_temp.reg('08.01 epicrisis del tramo 1: la reparación es un «hecho», con el daño que resuelve, la duración, «1 activo(s) más» y las fotos',
     exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'intervencion' and i ->> 'grupo' = 'hecho' and i ->> 'estado' = 'Cerrada'
              and i ->> 'resumen' = v_ia || ' · Reparación · atiende ' || v_d1 || ' (lo resuelve) · EMDUPAR · duración 2 h 00 min · 1 activo(s) más · 2 foto(s)')
     and exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'dano' and i ->> 'estado' = 'Atendido'), v_r::text);
  perform pg_temp.reg('08.02 la válvula también intervenida la tiene en su epicrisis, con el principal', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_val) -> 'items') i
     where i ->> 'clase' = 'intervencion' and i ->> 'resumen' = v_ia || ' · Reparación · también intervenido (principal ' || v_red1 || ')'));
  perform pg_temp.reg('08.03 el tramo nuevo: su alta dice «(inversión ITV-…)» y tiene la intervención', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_nuevo_red) -> 'items') i
     where i ->> 'clase' = 'alta' and i ->> 'resumen' = 'Alta del activo (inversión ' || v_id_txt || ')')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_nuevo_red) -> 'items') i where i ->> 'clase' = 'intervencion' and i ->> 'resumen' like v_id_txt || ' · Inversión (activo nuevo) · programada o mejora%')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_nuevo_red) -> 'items') i where i ->> 'clase' = 'evento_por_verificar'));
  perform pg_temp.reg('08.04 la ficha del tramo 1 cuenta 3 hechos (sus 2 daños y la intervención) y la del tramo nuevo dice «por verificar»',
     (public.geoportal_redes_activo(op, v_red1) -> 'epicrisis' ->> 'hechos')::integer = 3 and (public.geoportal_redes_activo(op, v_nuevo_red) -> 'activo' ->> 'por_verificar')::boolean);
  perform pg_temp.reg('08.05 el operador no ve autores en la epicrisis; el supervisor sí', not exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red1) -> 'items') i where i ? 'autor')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(sv, v_red1) -> 'items') i where i ->> 'autor' = op and i ->> 'clase' = 'intervencion'));
  perform pg_temp.reg('08.06 la intervención «sin evidencia» lo dice en la epicrisis de la torre', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_tor) -> 'items') i
     where i ->> 'resumen' = v_ic || ' · Mantenimiento preventivo · programada o mejora · contratista Obras ZT SAS · duración 2 h 00 min · sin evidencia fotográfica'));

  -- ---------- 09 Supervisor: lista y recursos (D-8) ----------
  perform pg_temp.err('09.01 el operador no ve la lista de intervenciones', format($$select public.geoportal_redes_intervenciones(%L)$$, op), '42501');
  v_r := public.geoportal_redes_intervenciones(sv, 'recursos_por_completar');
  perform pg_temp.reg('09.02 «recursos por completar»: la reparación sí; la del supervisor (con valores) no',
     exists (select 1 from jsonb_array_elements(v_r -> 'intervenciones') x where x ->> 'codigo' = v_ia and x ->> 'autor' = op and x -> 'fuentes' -> 0 ->> 'aportante' = 'emdupar')
     and not exists (select 1 from jsonb_array_elements(v_r -> 'intervenciones') x where x ->> 'codigo' = v_ic), left(v_r::text, 600));
  perform pg_temp.err('09.03 el operador no completa recursos', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar", "valor": 1}]')$$, op, v_ia), '42501');
  perform pg_temp.err('09.04 completar sin valor ni porcentaje', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar"}]')$$, sv, v_ia), '22023', 'valor o su porcentaje');
  perform pg_temp.err('09.05 porcentajes que suman más de 100', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar", "porcentaje": 70}, {"aportante": "nacion", "porcentaje": 40}]')$$, sv, v_ia), '22023', 'más de 100');
  v_r := public.geoportal_redes_intervencion_recursos(sv, lower(v_ia), '[{"aportante": "emdupar", "valor": 2500000, "porcentaje": 100, "soporte": "Presupuesto de mantenimiento 2026"}]');
  perform pg_temp.reg('09.06 el supervisor completa: versión 2, recursos completos y el evento; la versión 1 sigue ahí', (v_r ->> 'version')::integer = 2 and v_r ->> 'recursos' = 'completos'
     and (select count(*) from redes.intervencion_fuentes x join redes.intervenciones i on i.id = x.intervencion_id where i.codigo = v_ia) = 2
     and exists (select 1 from redes.intervencion_eventos e join redes.intervenciones i on i.id = e.intervencion_id where i.codigo = v_ia and e.tipo = 'completar_recursos' and e.autor = sv), v_r::text);
  perform pg_temp.err('09.07 cambiar recursos completos sin motivo', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar", "valor": 1}]')$$, sv, v_ia), '22023', 'motivo');
  v_r := public.geoportal_redes_intervencion_recursos(a, v_ia, '[{"aportante": "emdupar", "valor": 2600000}]', 'Se corrigió el valor con la factura');
  perform pg_temp.reg('09.08 con motivo, el administrador los cambia (versión 3)', (v_r ->> 'version')::integer = 3);

  -- ---------- 10 Bandeja de no identificados y «asociar activo» ----------
  v_dn := pg_temp.dano(op, jsonb_build_object('activo', null, 'no_identificado', 'Fuga en un tubo que no sale', 'lat', pg_temp.lat(3), 'lon', pg_temp.lon(150), 'ubicacion_origen', 'mapa')) ->> 'codigo';
  perform pg_temp.err('10.01 el operador no ve la bandeja', format($$select public.geoportal_redes_no_identificados(%L)$$, op), '42501');
  v_r := public.geoportal_redes_no_identificados(sv, 100);
  perform pg_temp.reg('10.02 la bandeja trae la intervención y el daño no identificados, con los activos más cercanos propuestos',
     exists (select 1 from jsonb_array_elements(v_r -> 'items') x where x ->> 'clase' = 'intervencion' and x ->> 'codigo' = v_if and x ->> 'que_es' = 'Cámara que no sale en el mapa'
              and x -> 'propuestos' -> 0 ->> 'codigo' = v_poz2 and (x -> 'propuestos' -> 0 ->> 'distancia_m')::numeric < 10)
     and exists (select 1 from jsonb_array_elements(v_r -> 'items') x where x ->> 'clase' = 'dano' and x ->> 'codigo' = v_dn and x -> 'propuestos' -> 0 ->> 'codigo' = v_red2), left(v_r::text, 600));
  perform pg_temp.err('10.03 asociar sin motivo', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'ok')$$, sv, v_if, v_poz2), '22023', 'motivo');
  perform pg_temp.err('10.04 asociar un activo de otro sistema', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'Es la cámara de la esquina')$$, sv, v_if, v_red1), '22023', 'mismo sistema');
  perform pg_temp.err('10.05 el operador no asocia', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'Es la cámara de la esquina')$$, op, v_if, v_poz2), '42501');
  v_r := public.geoportal_redes_asociar_activo(sv, 'intervencion', v_if, v_poz2, 'Es el pozo de la esquina, según el supervisor');
  perform pg_temp.reg('10.06 asociar la intervención al pozo 2: queda con activo (evento, sin reescribir), sale de la bandeja y entra a su epicrisis',
     v_r ->> 'activo' = v_poz2 and (select activo_codigo from redes.v_intervencion where codigo = v_if) = v_poz2
     and (select activo_id from redes.intervenciones where codigo = v_if) is null
     and not exists (select 1 from redes.v_no_identificados where codigo = v_if)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_poz2) -> 'items') i where i ->> 'clase' = 'intervencion' and i ->> 'resumen' like v_if || ' ·%'));
  perform pg_temp.err('10.07 asociar dos veces', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'Otra vez el mismo pozo')$$, sv, v_if, v_poz1), '22023', 'ya tiene activo');
  v_r := public.geoportal_redes_asociar_activo(a, 'dano', v_dn, v_red2, 'El tubo es el lateral de prueba');
  perform pg_temp.reg('10.08 asociar el daño no identificado al tramo 2: v_dano lo toma y entra a la epicrisis del tramo', (select activo_codigo from redes.v_dano where codigo = v_dn) = v_red2
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red2) -> 'items') i where i ->> 'clase' = 'dano' and i ->> 'resumen' like v_dn || ' ·%'));

  -- ---------- 11 Daño sin fotos (respuesta 2 de David al Corte 2) ----------
  perform pg_temp.err('11.01 el operador no prepara un daño sin fotos', format($$select public.geoportal_redes_preparar_dano(%L, 0)$$, op), '22023', 'de 1 a 6 fotos');
  v_p := public.geoportal_redes_preparar_dano(sv, 0); v_ida := (v_p ->> 'dano_id')::uuid;
  perform pg_temp.reg('11.02 el supervisor sí, y la preparación no trae rutas', jsonb_array_length(v_p -> 'fotos') = 0);
  perform pg_temp.err('11.03 el supervisor sin fotos y sin el motivo', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, sv, v_ida,
     jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(160), 'ubicacion_origen', 'activo',
       't_detectado', pg_temp.iso('-1 hours'), 'tipo_rotura', 'fisura', 'riesgo', 'bajo', 'causa_clase', 'desconocida', 'fotos', '[]'::jsonb)), '22023', 'por qué no hay evidencia');
  v_r := public.geoportal_redes_crear_dano(sv, v_ida, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(160),
            'ubicacion_origen', 'activo', 't_detectado', pg_temp.iso('-1 hours'), 'tipo_rotura', 'fisura', 'riesgo', 'bajo', 'causa_clase', 'desconocida', 'fotos', '[]'::jsonb,
            'sin_evidencia_motivo', 'Llegó por la línea 116, sin fotos'));
  perform pg_temp.reg('11.04 se guarda «sin evidencia fotográfica», con su nota, y la epicrisis lo dice', (v_r ->> 'sin_evidencia')::boolean and v_r ->> 'estado' = 'reportado'
     and exists (select 1 from redes.dano_eventos where dano_id = v_ida and tipo = 'nota' and motivo = 'Sin evidencia fotográfica: Llegó por la línea 116, sin fotos')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red2) -> 'items') i where i ->> 'resumen' like (v_r ->> 'codigo') || ' %sin evidencia fotográfica'), v_r::text);
  v_p := public.geoportal_redes_preparar_dano(op, 1); v_ida := (v_p ->> 'dano_id')::uuid;
  perform pg_temp.err('11.05 el operador manda 0 fotos aunque escriba el motivo', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_ida,
     jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(160), 'ubicacion_origen', 'gps',
       't_detectado', pg_temp.iso('-1 hours'), 'tipo_rotura', 'fisura', 'riesgo', 'bajo', 'causa_clase', 'desconocida', 'fotos', '[]'::jsonb, 'sin_evidencia_motivo', 'No tengo cámara hoy')), '22023', 'de 1 a 6 fotos');
  perform pg_temp.reg('11.06 un daño con foto sigue igual que en el Corte 2 (no queda «sin evidencia»)', not (pg_temp.dano(op, '{}') ->> 'sin_evidencia')::boolean);

  -- ---------- 12 Hechos de solo inserción y coherencia ----------
  perform pg_temp.err('12.01 una intervención no se cambia', $$update redes.intervenciones set descripcion = 'cambiada a mano'$$, '42501');
  perform pg_temp.err('12.02 una fuente no se borra', $$delete from redes.intervencion_fuentes$$, '42501');
  perform pg_temp.err('12.03 los archivos no se vacían', $$truncate redes.intervencion_archivos$$, '42501');
  perform pg_temp.err('12.04 un evento no se cambia', $$update redes.intervencion_eventos set tipo = 'nota'$$, '42501');
  perform pg_temp.err('12.05 la regla de la tabla: un preventivo no nace de un daño', format($$insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon,
       ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor, no_ident_que_es) select gen_random_uuid(), 'ITV-999999', 'dano', d.id, 'preventivo', 'acueducto', null, 10.47, -73.24, 'mapa', now() - interval '1 hour', now(),
       'Directo a la tabla', 'emdupar', 'x', 'Prueba directa' from redes.danos d where d.codigo = %L$$, v_d1), '23514', 'no nace de un daño');
  perform pg_temp.err('12.06 la regla de la tabla: también intervenido de otro sistema', format($$insert into redes.intervencion_activos (intervencion_id, activo_id, n)
       select i.id, a.id, 9 from redes.intervenciones i, redes.activos a where i.codigo = %L and a.codigo = %L$$, v_ia, v_poz1), '23514');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 3a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
